#!/usr/bin/env python3
"""Validate the one canonical public HTTPS origin used for VPS promotion."""

from __future__ import annotations

import argparse
import ipaddress
import re
import sys
from urllib.parse import urlsplit


HOST_PATTERN = re.compile(
    r"(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
    r"(?:[a-z]{2,63}|xn--[a-z0-9-]{2,59})\Z"
)


def canonical_origin(value: str) -> str:
    if not value or value != value.strip() or any(char.isspace() for char in value):
        raise ValueError("origin contains whitespace")
    parsed = urlsplit(value)
    if (
        parsed.scheme != "https"
        or parsed.path
        or parsed.query
        or parsed.fragment
        or parsed.username
        or parsed.password
        or parsed.port is not None
        or parsed.hostname is None
    ):
        raise ValueError("origin must be one exact HTTPS hostname without a port")
    hostname = parsed.hostname
    if hostname != hostname.lower() or HOST_PATTERN.fullmatch(hostname) is None:
        raise ValueError("origin hostname is not canonical DNS")
    try:
        ipaddress.ip_address(hostname)
    except ValueError:
        pass
    else:
        raise ValueError("IP origins are forbidden")
    origin = f"https://{hostname}"
    if value != origin:
        raise ValueError("origin is not canonical")
    return origin


def main() -> int:
    parser = argparse.ArgumentParser()
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument("--host")
    selection.add_argument("--origin")
    args = parser.parse_args()
    value = args.origin if args.origin is not None else f"https://{args.host}"
    try:
        print(canonical_origin(value))
    except ValueError as exc:
        print(f"public origin error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
