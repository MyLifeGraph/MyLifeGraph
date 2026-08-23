import base64
import contextlib
import io
import json
import sqlite3
import sys
import traceback

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import scipy.stats as stats
import statsmodels.api as sm


MAX_STDOUT = 100_000
MAX_IMAGES = 1
MAX_IMAGE_BYTES = 300_000
MAX_QUERY_CHARS = 2_000
MAX_TABLES = 100
ALLOWED_SQLITE_ACTIONS = {
    sqlite3.SQLITE_SELECT,
    sqlite3.SQLITE_READ,
    sqlite3.SQLITE_FUNCTION,
    sqlite3.SQLITE_RECURSIVE,
}
DENIED_FUNCTIONS = {
    "edit",
    "fts3_tokenizer",
    "load_extension",
    "readfile",
    "shell",
    "writefile",
}


def main() -> None:
    queries: list[str] = []
    tables: set[str] = set()
    try:
        request = json.load(sys.stdin)
        if not isinstance(request, dict) or set(request) != {"code"}:
            raise ValueError("Analysis input is invalid.")
        code = request["code"]
        if not isinstance(code, str) or not code.strip() or len(code) > 30_000:
            raise ValueError("Analysis code is invalid.")
        database_uri = "file:/data/personal.sqlite?mode=ro&immutable=1"
        conn = sqlite3.connect(database_uri, uri=True)
        conn.execute("PRAGMA query_only=ON")
        conn.execute("PRAGMA trusted_schema=OFF")
        conn.setlimit(sqlite3.SQLITE_LIMIT_LENGTH, 1024 * 1024)
        conn.setlimit(sqlite3.SQLITE_LIMIT_SQL_LENGTH, 10_000)
        conn.setlimit(sqlite3.SQLITE_LIMIT_COLUMN, 200)
        conn.setlimit(sqlite3.SQLITE_LIMIT_COMPOUND_SELECT, 50)
        conn.setlimit(sqlite3.SQLITE_LIMIT_EXPR_DEPTH, 100)
        conn.setlimit(sqlite3.SQLITE_LIMIT_FUNCTION_ARG, 100)
        conn.setlimit(sqlite3.SQLITE_LIMIT_LIKE_PATTERN_LENGTH, 1_000)
        conn.setlimit(sqlite3.SQLITE_LIMIT_VARIABLE_NUMBER, 999)

        def authorize(
            action: int,
            argument1: str | None,
            argument2: str | None,
            database: str | None,
            trigger: str | None,
        ) -> int:
            del trigger
            function_name = (argument1 or argument2 or "").lower()
            if action == sqlite3.SQLITE_FUNCTION and function_name in DENIED_FUNCTIONS:
                return sqlite3.SQLITE_DENY
            if action not in ALLOWED_SQLITE_ACTIONS:
                return sqlite3.SQLITE_DENY
            # SQLite reports the database as None for column-free reads such
            # as COUNT(*), even though the table belongs to main.
            if action == sqlite3.SQLITE_READ and database in {None, "main"}:
                if (
                    not isinstance(argument1, str)
                    or not 1 <= len(argument1) <= 128
                    or not (
                        argument1[0] == "_"
                        or "a" <= argument1[0] <= "z"
                    )
                    or not all(
                        character == "_"
                        or "a" <= character <= "z"
                        or "0" <= character <= "9"
                        for character in argument1
                    )
                ):
                    return sqlite3.SQLITE_DENY
                if argument1 not in tables and len(tables) >= MAX_TABLES:
                    return sqlite3.SQLITE_DENY
                tables.add(argument1)
            return sqlite3.SQLITE_OK

        conn.set_authorizer(authorize)
        conn.set_trace_callback(
            lambda statement: queries.append(statement[:MAX_QUERY_CHARS]),
        )
        output = io.StringIO()
        namespace = {
            "__builtins__": __builtins__,
            "conn": conn,
            "np": np,
            "pd": pd,
            "plt": plt,
            "sm": sm,
            "stats": stats,
            "SNAPSHOT_PATH": "/data/personal.sqlite",
        }
        try:
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                exec(compile(code, "<coach-analysis>", "exec"), namespace, namespace)
        finally:
            conn.close()
        images: list[str] = []
        for figure_number in plt.get_fignums()[:MAX_IMAGES]:
            buffer = io.BytesIO()
            plt.figure(figure_number).savefig(
                buffer,
                format="png",
                dpi=110,
                bbox_inches="tight",
            )
            raw = buffer.getvalue()
            if len(raw) <= MAX_IMAGE_BYTES:
                images.append(base64.b64encode(raw).decode("ascii"))
        plt.close("all")
        rendered = output.getvalue()
        if len(rendered.encode("utf-8")) > MAX_STDOUT:
            rendered = rendered.encode("utf-8")[:MAX_STDOUT].decode(
                "utf-8",
                errors="ignore",
            )
            rendered += "\n[output truncated at 100,000 bytes]"
        response = {
            "ok": True,
            "stdout": rendered,
            "error": None,
            "queries": queries[:50],
            "tables": sorted(tables),
            "images": images,
        }
    except BaseException as exc:
        response = {
            "ok": False,
            "stdout": "",
            "error": f"{type(exc).__name__}: {str(exc)[:400]}",
            "queries": queries[:50],
            "tables": sorted(tables),
            "images": [],
        }
        traceback.clear_frames(exc.__traceback__)
    sys.stdout.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
