#!/usr/bin/env python3
"""Compare normalized schema-only dumps without printing their contents."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


ASSOCIATIVE_CHECK_CONSTRAINTS = {
    "multi_exam_plan_batch_items_shape_check",
    "multi_exam_plan_batch_links_shape_check",
    "assignment_series_shape_check",
    "assignment_series_items_shape_check",
    "assignment_series_revisions_input_check",
    "calendar_connections_label_length",
    "calendar_events_text_bounds",
    "calendar_imports_counts",
    "deadline_plan_blocks_recovery_check",
    "deadline_plan_blocks_shape_check",
    "focus_session_reflections_obstacles_check",
    "planner_habit_slots_shape_check",
    "planner_task_blocks_recovery_check",
    "planner_task_blocks_shape_check",
    "profiles_daily_preparation_budget_minutes_check",
}
CHECK_LINE = re.compile(
    r"^(?P<prefix>\s*CONSTRAINT\s+(?P<name>[a-z_][a-z0-9_]*)\s+CHECK\s*)"
    r"\((?P<expression>.*)\)(?P<suffix>\s*(?:NOT VALID)?[,]?)$"
)


def _matching_outer_parentheses(value: str) -> bool:
    if not value.startswith("(") or not value.endswith(")"):
        return False
    depth = 0
    quote: str | None = None
    index = 0
    while index < len(value):
        char = value[index]
        if quote is not None:
            if char == quote:
                if index + 1 < len(value) and value[index + 1] == quote:
                    index += 2
                    continue
                quote = None
            index += 1
            continue
        if char in {"'", '"'}:
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0 and index != len(value) - 1:
                return False
            if depth < 0:
                return False
        index += 1
    return depth == 0 and quote is None


def _strip_outer_parentheses(value: str) -> str:
    result = value.strip()
    while _matching_outer_parentheses(result):
        result = result[1:-1].strip()
    return result


def _split_top_level(value: str, keyword: str) -> list[str]:
    parts: list[str] = []
    depth = 0
    quote: str | None = None
    start = 0
    index = 0
    upper = value.upper()
    while index < len(value):
        char = value[index]
        if quote is not None:
            if char == quote:
                if index + 1 < len(value) and value[index + 1] == quote:
                    index += 2
                    continue
                quote = None
            index += 1
            continue
        if char in {"'", '"'}:
            quote = char
            index += 1
            continue
        if char == "(":
            depth += 1
            index += 1
            continue
        if char == ")":
            depth -= 1
            index += 1
            continue
        end = index + len(keyword)
        if (
            depth == 0
            and upper[index:end] == keyword
            and (
                index == 0
                or not (value[index - 1].isalnum() or value[index - 1] == "_")
            )
            and (
                end == len(value)
                or not (value[end].isalnum() or value[end] == "_")
            )
        ):
            parts.append(value[start:index].strip())
            start = end
            index = end
            continue
        index += 1
    if not parts:
        return [value.strip()]
    parts.append(value[start:].strip())
    return parts


def _canonical_boolean(value: str) -> str:
    expression = _strip_outer_parentheses(value)
    for operator in ("OR", "AND"):
        parts = _split_top_level(expression, operator)
        if len(parts) > 1:
            prefix = f"{operator}("
            canonical_parts: list[str] = []
            for part in parts:
                canonical = _canonical_boolean(part)
                if canonical.startswith(prefix) and canonical.endswith(")"):
                    canonical_parts.append(canonical[len(prefix) : -1])
                else:
                    canonical_parts.append(canonical)
            return prefix + ",".join(canonical_parts) + ")"
    return re.sub(r"\s+", " ", expression).strip()


def _canonical_line(line: str) -> str:
    match = CHECK_LINE.fullmatch(line.rstrip())
    if match is None or match.group("name") not in ASSOCIATIVE_CHECK_CONSTRAINTS:
        return line.rstrip()
    return (
        match.group("prefix")
        + "("
        + _canonical_boolean(match.group("expression"))
        + ")"
        + match.group("suffix")
    )


def _normalized(path: Path) -> bytes:
    kept: list[str] = []
    for line in path.read_text(encoding="utf-8", errors="strict").splitlines():
        stripped = line.strip()
        if (
            not stripped
            or stripped.startswith("--")
            or stripped.startswith("\\restrict ")
            or stripped.startswith("\\unrestrict ")
        ):
            continue
        kept.append(_canonical_line(line))
    return ("\n".join(kept) + "\n").encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--restored", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        restored = hashlib.sha256(_normalized(Path(args.restored))).hexdigest()
        reference = hashlib.sha256(_normalized(Path(args.reference))).hexdigest()
        result = {
            "schema_version": "mylifegraph-schema-comparison-v2",
            "normalization": {
                "acl_authority": "strict-schema-digest",
                "boolean_check_constraints": sorted(
                    ASSOCIATIVE_CHECK_CONSTRAINTS
                ),
            },
            "restored_sha256": restored,
            "reference_sha256": reference,
            "match": restored == reference,
        }
        Path(args.output).write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if restored != reference:
            print("restore schema differs from repository reference", file=sys.stderr)
            return 1
    except (OSError, UnicodeError) as exc:
        print(f"schema comparison error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
