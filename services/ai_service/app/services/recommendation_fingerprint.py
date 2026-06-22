import hashlib
import json

from app.models.user_context import EvidenceRef


def build_recommendation_fingerprint(
    *,
    rule_id: str,
    period_key: str,
    evidence_refs: list[EvidenceRef],
    source_engine_version: str = "deterministic-v1",
) -> str:
    evidence_payload = [
        {
            "table": ref.table,
            "id": ref.id,
            "field": ref.field,
        }
        for ref in sorted(evidence_refs, key=lambda ref: (ref.table, ref.id, ref.field))
    ]
    payload = {
        "rule_id": rule_id,
        "period_key": period_key,
        "evidence_refs": evidence_payload,
    }
    digest = hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8"),
    ).hexdigest()[:12]
    return f"{source_engine_version}:{rule_id}:{period_key}:{digest}"
