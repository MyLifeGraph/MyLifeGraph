#!/usr/bin/env python3
"""Check liveness/readiness and exact immutable release identity."""

from __future__ import annotations

import argparse
import json
import re
import ssl
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import (
    HTTPHandler,
    HTTPRedirectHandler,
    HTTPSHandler,
    Request,
    build_opener,
)


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _database_contract(
    value: object,
    *,
    expected_prefix: tuple[str, int, str],
) -> tuple[str, int, str]:
    if not isinstance(value, dict) or set(value) != {
        "contract_version",
        "migration_head",
        "migration_count",
        "migration_identity_sha256",
        "prefix_head",
        "prefix_count",
        "prefix_identity_sha256",
        "prepared_deletion_pending_guard",
    }:
        raise RuntimeError("database contract shape is invalid")
    migration_head = value["migration_head"]
    migration_count = value["migration_count"]
    migration_identity_sha256 = value["migration_identity_sha256"]
    prefix = (
        value["prefix_head"],
        value["prefix_count"],
        value["prefix_identity_sha256"],
    )
    if (
        value["contract_version"] != "hosted-database-contract-v1"
        or value["prepared_deletion_pending_guard"] is not True
        or not isinstance(migration_head, str)
        or re.fullmatch(r"[0-9]{14}_[a-z0-9_]+\.sql", migration_head) is None
        or type(migration_count) is not int
        or migration_count < 1
        or migration_count > 50_000
        or not isinstance(migration_identity_sha256, str)
        or re.fullmatch(r"[0-9a-f]{64}", migration_identity_sha256) is None
        or prefix != expected_prefix
    ):
        raise RuntimeError("database contract values are invalid")
    return migration_head, migration_count, migration_identity_sha256


def _get_json(url: str, timeout: float) -> dict[str, object]:
    request = Request(url, headers={"Accept": "application/json"})
    opener = build_opener(
        HTTPHandler(),
        HTTPSHandler(context=ssl.create_default_context()),
        _NoRedirect(),
    )
    try:
        with opener.open(request, timeout=timeout) as response:
            if response.status != 200:
                raise RuntimeError(f"unexpected HTTP status {response.status}")
            if response.geturl() != url:
                raise RuntimeError("endpoint changed its exact URL")
            if response.headers.get_content_type() != "application/json":
                raise RuntimeError("response is not JSON")
            raw = response.read(65_537)
    except (HTTPError, URLError, TimeoutError, OSError) as exc:
        raise RuntimeError("endpoint is unavailable") from exc
    if len(raw) > 65_536:
        raise RuntimeError("response exceeds the health-check bound")
    try:
        value = json.loads(raw)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("response JSON is invalid") from exc
    if not isinstance(value, dict):
        raise RuntimeError("response JSON is not an object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--expected-sha")
    parser.add_argument("--expected-tag")
    parser.add_argument("--expected-migration-head")
    parser.add_argument("--expected-migration-count", type=int)
    parser.add_argument("--expected-migration-identity-sha256")
    parser.add_argument("--database-contract-only", action="store_true")
    parser.add_argument("--timeout", type=float, default=5)
    args = parser.parse_args()
    parsed = urlsplit(args.base_url)
    if parsed.scheme not in {"http", "https"} or parsed.query or parsed.fragment:
        parser.error("base URL must be an exact HTTP(S) origin")
    if parsed.path not in {"", "/"} or parsed.username or parsed.password:
        parser.error("base URL must not contain credentials or a path")
    if args.database_contract_only:
        if args.expected_sha is not None or args.expected_tag is not None:
            parser.error("database-contract-only does not accept app identity")
        if None in (
            args.expected_migration_head,
            args.expected_migration_count,
            args.expected_migration_identity_sha256,
        ):
            parser.error("database-contract-only requires migration prefix identity")
        try:
            query = urlencode({"through_head": args.expected_migration_head})
            contract = _get_json(
                f"{args.base_url.rstrip('/')}/v1/internal/database-contract?{query}",
                args.timeout,
            )
            migration_head, migration_count, migration_identity_sha256 = (
                _database_contract(
                    contract,
                    expected_prefix=(
                        args.expected_migration_head,
                        args.expected_migration_count,
                        args.expected_migration_identity_sha256,
                    ),
                )
            )
        except RuntimeError as exc:
            print(f"health check failed: {exc}", file=sys.stderr)
            return 1
        print(
            migration_head,
            migration_count,
            migration_identity_sha256,
            sep="\t",
        )
        return 0
    if None in (
        args.expected_sha,
        args.expected_tag,
        args.expected_migration_head,
        args.expected_migration_count,
        args.expected_migration_identity_sha256,
    ):
        parser.error("release health requires SHA, tag, and migration head")
    if re.fullmatch(r"[0-9a-f]{40}", args.expected_sha) is None:
        parser.error("expected SHA is invalid")
    if (
        re.fullmatch(
            r"[0-9]{14}_[a-z0-9_]+\.sql",
            args.expected_migration_head,
        )
        is None
    ):
        parser.error("expected migration head is invalid")
    if args.expected_migration_count < 1 or args.expected_migration_count > 50_000:
        parser.error("expected migration count is invalid")
    if (
        re.fullmatch(r"[0-9a-f]{64}", args.expected_migration_identity_sha256)
        is None
    ):
        parser.error("expected migration identity digest is invalid")
    try:
        health = _get_json(f"{args.base_url.rstrip('/')}/v1/health", args.timeout)
        if health != {
            "status": "ok",
            "release_sha": args.expected_sha,
            "release_tag": args.expected_tag,
        }:
            raise RuntimeError("liveness release identity does not match")
        ready = _get_json(f"{args.base_url.rstrip('/')}/v1/ready", args.timeout)
        if ready != {
            "status": "ready",
            "migration_head": args.expected_migration_head,
            "migration_count": args.expected_migration_count,
            "migration_identity_sha256": (
                args.expected_migration_identity_sha256
            ),
        }:
            raise RuntimeError("core readiness response does not match")
    except RuntimeError as exc:
        print(f"health check failed: {exc}", file=sys.stderr)
        return 1
    print(f"health check passed: {args.expected_tag} {args.expected_sha[:12]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
