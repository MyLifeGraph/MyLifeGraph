#!/usr/bin/env python3
"""Fetch and sanitize Supabase Auth configuration without persisting secrets."""

from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import os
import re
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, HTTPSHandler, Request, build_opener


MAX_RESPONSE_BYTES = 1024 * 1024
PROJECT_REF = re.compile(r"[a-z]{20}")
NATIVE_REDIRECT = "com.mylifegraph.app://login-callback/"
EMAIL_TEMPLATE_KINDS = (
    "invite",
    "confirmation",
    "recovery",
    "email_change",
    "magic_link",
    "reauthentication",
    "password_changed_notification",
    "email_changed_notification",
)
REQUIRED_RATE_LIMITS = (
    "rate_limit_email_sent",
    "rate_limit_token_refresh",
    "rate_limit_verify",
)


class AuthConfigInventoryError(ValueError):
    pass


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _required_bool(value: dict[str, Any], key: str) -> bool:
    result = value.get(key)
    if not isinstance(result, bool):
        raise AuthConfigInventoryError(f"Auth config field is missing or invalid: {key}")
    return result


def _optional_string(value: dict[str, Any], key: str) -> str:
    result = value.get(key)
    if result is None:
        return ""
    if not isinstance(result, str) or len(result) > 8192:
        raise AuthConfigInventoryError(f"Auth config field is invalid: {key}")
    return result


def _optional_positive_int(value: dict[str, Any], key: str) -> int | None:
    result = value.get(key)
    if isinstance(result, str) and result.isdigit():
        result = int(result)
    if result is None:
        return None
    if isinstance(result, bool) or not isinstance(result, int) or result < 0:
        raise AuthConfigInventoryError(f"Auth config field is invalid: {key}")
    return result


def _canonical_https_url(value: str, *, allow_path: bool) -> str:
    from urllib.parse import urlsplit

    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError as exc:
        raise AuthConfigInventoryError("Auth URL is invalid") from exc
    host = parsed.hostname or ""
    try:
        ipaddress.ip_address(host)
        is_ip = True
    except ValueError:
        is_ip = False
    if (
        parsed.scheme != "https"
        or not host
        or host == "localhost"
        or "." not in host
        or "*" in host
        or is_ip
        or parsed.username is not None
        or parsed.password is not None
        or port is not None
        or parsed.query
        or parsed.fragment
        or (not allow_path and parsed.path not in {"", "/"})
    ):
        raise AuthConfigInventoryError("Auth URL is not canonical HTTPS")
    return value


def _canonical_redirect(value: str) -> str:
    if value == NATIVE_REDIRECT:
        return value
    return _canonical_https_url(value, allow_path=True)


def sanitize(
    config: dict[str, Any],
    project_ref: str,
    expected_app_origin: str,
    expected_turnstile_site_key: str,
    realtime_config: dict[str, Any] | None = None,
) -> tuple[dict[str, object], dict[str, object]]:
    if PROJECT_REF.fullmatch(project_ref) is None:
        raise AuthConfigInventoryError("project ref is invalid")
    expected_origin = _canonical_https_url(
        expected_app_origin,
        allow_path=False,
    ).removesuffix("/")
    expected_redirects = {f"{expected_origin}/", NATIVE_REDIRECT}
    if re.fullmatch(r"[A-Za-z0-9_-]{20,128}", expected_turnstile_site_key) is None:
        raise AuthConfigInventoryError("Turnstile site key is invalid")
    site_url = _canonical_https_url(
        _optional_string(config, "site_url"), allow_path=False
    ).removesuffix("/")
    raw_allow_list = _optional_string(config, "uri_allow_list")
    redirect_urls = sorted(
        {
            _canonical_redirect(item.strip())
            for item in raw_allow_list.split(",")
            if item.strip()
        }
    )
    if not redirect_urls:
        raise AuthConfigInventoryError("Auth redirect allowlist is empty")
    email_enabled = _required_bool(config, "external_email_enabled")
    disable_signup = _required_bool(config, "disable_signup")
    mailer_autoconfirm = _required_bool(config, "mailer_autoconfirm")
    google_enabled = _required_bool(config, "external_google_enabled")
    captcha_enabled = _required_bool(config, "security_captcha_enabled")
    captcha_provider = _optional_string(config, "security_captcha_provider")
    google_client_ids = [
        item.strip()
        for item in _optional_string(config, "external_google_client_id").split(",")
        if item.strip()
    ]
    smtp_host = _optional_string(config, "smtp_host")
    smtp_sender_name = _optional_string(config, "smtp_sender_name")
    smtp_admin_email = _optional_string(config, "smtp_admin_email")
    raw_smtp_port = config.get("smtp_port")
    if isinstance(raw_smtp_port, str) and raw_smtp_port.isdigit():
        smtp_port: int | None = int(raw_smtp_port)
    else:
        smtp_port = raw_smtp_port
    if smtp_port is not None and (
        isinstance(smtp_port, bool)
        or not isinstance(smtp_port, int)
        or not 1 <= smtp_port <= 65535
    ):
        raise AuthConfigInventoryError("Auth config field is invalid: smtp_port")
    violations: list[str] = []
    if site_url != expected_origin:
        violations.append("site_url_mismatch")
    redirect_set = set(redirect_urls)
    if f"{expected_origin}/" not in redirect_set:
        violations.append("web_redirect_missing")
    if NATIVE_REDIRECT not in redirect_set:
        violations.append("native_redirect_missing")
    if redirect_set - expected_redirects:
        violations.append("redirect_allowlist_unexpected")
    if not email_enabled:
        violations.append("email_provider_disabled")
    if disable_signup:
        violations.append("public_signup_disabled")
    if mailer_autoconfirm:
        violations.append("email_confirmation_disabled")
    if not smtp_host:
        violations.append("custom_smtp_host_missing")
    if smtp_port is None:
        violations.append("custom_smtp_port_missing")
    if not smtp_sender_name:
        violations.append("custom_smtp_sender_name_missing")
    if not smtp_admin_email:
        violations.append("custom_smtp_admin_email_missing")
    if google_enabled and not google_client_ids:
        violations.append("google_client_id_missing")
    if not captcha_enabled:
        violations.append("captcha_disabled")
    elif captcha_provider != "turnstile":
        violations.append("captcha_provider_mismatch")
    templates: dict[str, dict[str, object]] = {}
    recovery_templates: dict[str, dict[str, str]] = {}
    for kind in EMAIL_TEMPLATE_KINDS:
        subject = _optional_string(config, f"mailer_subjects_{kind}")
        content = _optional_string(config, f"mailer_templates_{kind}_content")
        templates[kind] = {
            "subject_present": bool(subject),
            "content_present": bool(content),
            "subject_sha256": (
                hashlib.sha256(subject.encode("utf-8")).hexdigest()
                if subject
                else None
            ),
            "content_sha256": (
                hashlib.sha256(content.encode("utf-8")).hexdigest()
                if content
                else None
            ),
        }
        recovery_templates[kind] = {"subject": subject, "content": content}
    for required_template in ("confirmation", "recovery"):
        if not templates[required_template]["subject_present"]:
            violations.append(f"{required_template}_email_subject_missing")
        if not templates[required_template]["content_present"]:
            violations.append(f"{required_template}_email_template_missing")
    rate_limits = {
        key: _optional_positive_int(config, key)
        for key in sorted(key for key in config if key.startswith("rate_limit_"))
    }
    for required_limit in REQUIRED_RATE_LIMITS:
        if rate_limits.get(required_limit) in {None, 0}:
            violations.append(f"{required_limit}_missing")
    realtime: dict[str, object]
    if realtime_config is None:
        realtime = {"available": False}
        violations.append("realtime_config_unavailable")
    else:
        selected_realtime: dict[str, object] = {}
        for key in (
            "private_only",
            "connection_pool",
            "max_concurrent_users",
            "max_events_per_second",
            "max_bytes_per_second",
            "max_channels_per_client",
            "max_joins_per_second",
            "max_presence_events_per_second",
            "max_payload_size_in_kb",
            "suspend",
            "presence_enabled",
        ):
            value = realtime_config.get(key)
            if not isinstance(value, (bool, int)) or isinstance(value, float):
                raise AuthConfigInventoryError(
                    f"Realtime config field is missing or invalid: {key}"
                )
            selected_realtime[key] = value
        realtime = {"available": True, **selected_realtime}
        if realtime_config.get("suspend") is not False:
            violations.append("realtime_suspended")
    retrieved_at = (
        datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    )
    inventory: dict[str, object] = {
        "schema_version": "mylifegraph-auth-config-inventory-v1",
        "project_ref": project_ref,
        "policy_status": "compliant" if not violations else "noncompliant",
        "policy_violations": violations,
        "retrieved_at_utc": retrieved_at,
        "site_url": site_url,
        "redirect_allowlist": redirect_urls,
        "email": {
            "enabled": email_enabled,
            "signup_enabled": not disable_signup,
            "confirmation_required": not mailer_autoconfirm,
        },
        "smtp": {
            "custom_configured": bool(
                smtp_host
                and smtp_port is not None
                and smtp_sender_name
                and smtp_admin_email
            ),
            "host_present": bool(smtp_host),
            "port": smtp_port,
            "sender_name_present": bool(smtp_sender_name),
            "admin_email_present": bool(smtp_admin_email),
        },
        "captcha": {
            "enabled": captcha_enabled,
            "provider": captcha_provider,
            "site_key_sha256": hashlib.sha256(
                expected_turnstile_site_key.encode("ascii")
            ).hexdigest(),
        },
        "google_oauth": {
            "enabled": google_enabled,
            "client_id_count": len(google_client_ids),
        },
        "email_template_hashes": templates,
        "auth_rate_limits": rate_limits,
        "realtime": realtime,
    }
    recovery: dict[str, object] = {
        "schema_version": "mylifegraph-auth-config-recovery-v1",
        "project_ref": project_ref,
        "capture_status": "captured",
        "retrieved_at_utc": retrieved_at,
        "site_url": site_url,
        "redirect_allowlist": redirect_urls,
        "email": inventory["email"],
        "smtp": {
            "host": smtp_host,
            "port": smtp_port,
            "sender_name": smtp_sender_name,
            "admin_email": smtp_admin_email,
        },
        "captcha": {
            "provider": captcha_provider,
            "site_key": expected_turnstile_site_key,
        },
        "google_oauth": {
            "enabled": google_enabled,
            "client_ids": sorted(google_client_ids),
        },
        "email_templates": recovery_templates,
        "auth_rate_limits": rate_limits,
        "realtime": realtime,
    }
    return inventory, recovery


def _fetch(project_ref: str, suffix: str) -> dict[str, Any]:
    access_token = os.environ.get("SUPABASE_ACCESS_TOKEN", "")
    if not access_token:
        raise AuthConfigInventoryError("SUPABASE_ACCESS_TOKEN is missing")
    if suffix not in {"auth", "realtime"}:
        raise AuthConfigInventoryError("Management config endpoint is invalid")
    expected_url = f"https://api.supabase.com/v1/projects/{project_ref}/config/{suffix}"
    request = Request(
        expected_url,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/json",
            "User-Agent": "mylifegraph-pilot-backup/1",
        },
        method="GET",
    )
    opener = build_opener(HTTPSHandler(), _NoRedirect())
    try:
        with opener.open(request, timeout=15) as response:
            if response.status != 200:
                raise AuthConfigInventoryError("Auth config request failed")
            if response.geturl() != expected_url:
                raise AuthConfigInventoryError("Auth config request changed URL")
            content_length = response.headers.get("Content-Length")
            if content_length and int(content_length) > MAX_RESPONSE_BYTES:
                raise AuthConfigInventoryError("Auth config response is too large")
            raw = response.read(MAX_RESPONSE_BYTES + 1)
    except (HTTPError, URLError, TimeoutError, OSError, ValueError) as exc:
        raise AuthConfigInventoryError("Auth config request failed") from exc
    if len(raw) > MAX_RESPONSE_BYTES:
        raise AuthConfigInventoryError("Auth config response is too large")
    try:
        value = json.loads(raw)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise AuthConfigInventoryError("Auth config response is invalid") from exc
    if not isinstance(value, dict):
        raise AuthConfigInventoryError("Auth config response is not an object")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-ref", required=True)
    parser.add_argument("--expected-app-origin", required=True)
    parser.add_argument("--expected-turnstile-site-key", required=True)
    parser.add_argument("--input", help="test-only captured response")
    parser.add_argument("--output", required=True)
    parser.add_argument("--recovery-output", required=True)
    args = parser.parse_args()
    try:
        if args.input:
            captured = json.loads(Path(args.input).read_text(encoding="utf-8"))
            if not isinstance(captured, dict):
                raise AuthConfigInventoryError("Auth config fixture is not an object")
            if set(captured) == {"auth", "realtime"}:
                value = captured["auth"]
                realtime = captured["realtime"]
            else:
                value = captured
                realtime = None
            if not isinstance(value, dict) or (
                realtime is not None and not isinstance(realtime, dict)
            ):
                raise AuthConfigInventoryError("Auth config fixture is invalid")
            inventory, recovery = sanitize(
                value,
                args.project_ref,
                args.expected_app_origin,
                args.expected_turnstile_site_key,
                realtime,
            )
        else:
            try:
                inventory, recovery = sanitize(
                    _fetch(args.project_ref, "auth"),
                    args.project_ref,
                    args.expected_app_origin,
                    args.expected_turnstile_site_key,
                    _fetch(args.project_ref, "realtime"),
                )
            except AuthConfigInventoryError:
                inventory = {
                    "schema_version": "mylifegraph-auth-config-inventory-v1",
                    "project_ref": args.project_ref,
                    "policy_status": "unavailable",
                    "policy_violations": ["auth_config_inventory_unavailable"],
                    "retrieved_at_utc": datetime.now(UTC)
                    .replace(microsecond=0)
                    .isoformat()
                    .replace("+00:00", "Z"),
                }
                recovery = {
                    "schema_version": "mylifegraph-auth-config-recovery-v1",
                    "project_ref": args.project_ref,
                    "capture_status": "unavailable",
                }
        Path(args.output).write_text(
            json.dumps(inventory, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        Path(args.recovery_output).write_text(
            json.dumps(recovery, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except (AuthConfigInventoryError, OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"Auth config inventory error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
