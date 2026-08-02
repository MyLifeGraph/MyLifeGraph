"""Helpers for historical migration source guards.

These helpers deliberately inspect committed migration text. That evidence is
useful when a rolling-safe follow-up must retain an exact declaration, wrapper,
lock order, or grant statement in a particular historical file. It is not
evidence of the database's current effective schema or authority. Final-state
contracts belong in pgTAP tests that query catalogs, privileges, roles, and
behavior after the complete migration chain has been applied.

This is a small extractor for repository-owned migration conventions, not a
general SQL parser.
"""

import re
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS_DIR = REPOSITORY_ROOT / "supabase" / "migrations"


def migration_path(filename: str) -> Path:
    """Return the repository path for one versioned migration filename."""
    if Path(filename).name != filename or not filename.endswith(".sql"):
        raise ValueError("migration filename must be one SQL basename")
    return MIGRATIONS_DIR / filename


def load_migration(filename: str) -> str:
    """Load one historical migration as UTF-8 text."""
    return migration_path(filename).read_text(encoding="utf-8")


def normalize_sql(sql: str) -> str:
    """Lowercase SQL and collapse whitespace for source-identity assertions."""
    return " ".join(sql.lower().split())


def load_normalized_migration(filename: str) -> str:
    """Load and normalize one historical migration."""
    return normalize_sql(load_migration(filename))


def extract_function(sql: str, qualified_name: str) -> str:
    """Extract one CREATE FUNCTION statement including its closing delimiter."""
    marker = re.compile(
        rf"create\s+(?:or\s+replace\s+)?function\s+"
        rf"{re.escape(qualified_name)}\s*\(",
        flags=re.IGNORECASE,
    )
    match = marker.search(sql)
    if match is None:
        raise ValueError(f"function declaration not found: {qualified_name}")

    delimiter_match = re.search(r"\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$", sql[match.start() :])
    if delimiter_match is None:
        raise ValueError(f"function body delimiter not found: {qualified_name}")
    delimiter_start = match.start() + delimiter_match.start()
    delimiter = delimiter_match.group()
    delimiter_end = sql.find(delimiter, delimiter_start + len(delimiter))
    if delimiter_end < 0:
        raise ValueError(f"function closing delimiter not found: {qualified_name}")
    statement_end = delimiter_end + len(delimiter)
    if statement_end < len(sql) and sql[statement_end] == ";":
        statement_end += 1
    return sql[match.start() : statement_end]


def extract_policy(sql: str, policy_name: str) -> str:
    """Extract one literal CREATE POLICY statement."""
    name = re.escape(policy_name)
    marker = re.compile(
        rf"create\s+policy\s+(?:\"{name}\"|{name})(?=\s)",
        flags=re.IGNORECASE,
    )
    match = marker.search(sql)
    if match is None:
        raise ValueError(f"policy declaration not found: {policy_name}")
    statement_end = sql.find(";", match.start())
    if statement_end < 0:
        raise ValueError(f"policy terminator not found: {policy_name}")
    return sql[match.start() : statement_end + 1]


def extract_dropped_policy_names(sql: str) -> tuple[str, ...]:
    """Extract literal policy names from top-level DROP POLICY statements."""
    return tuple(
        match.group("quoted") or match.group("plain")
        for match in re.finditer(
            r"(?im)^\s*drop\s+policy(?:\s+if\s+exists)?\s+"
            r'(?:"(?P<quoted>[^"]+)"|(?P<plain>[a-z_][a-z0-9_]*))\s+on\s+',
            sql,
        )
    )


def _extract_command_statements(sql: str, command: str) -> tuple[str, ...]:
    return tuple(
        match.group().strip()
        for match in re.finditer(
            rf"(?im)^\s*{command}\s+[^;]+;",
            sql,
        )
    )


def extract_grants(sql: str) -> tuple[str, ...]:
    """Extract literal top-level GRANT statements from migration source."""
    return _extract_command_statements(sql, "grant")


def extract_revokes(sql: str) -> tuple[str, ...]:
    """Extract literal top-level REVOKE statements from migration source."""
    return _extract_command_statements(sql, "revoke")
