"""Cloud Run entry point for the Salesforce AI insights service.

Routes (all POST, JSON, protected by Cloud Run IAM - callers present a Google identity token):
    /api/v1/summarize  -> grounded case summary
    /api/v1/taxonomy   -> receive the live picklist taxonomy from Salesforce (hallucination gate)
    /api/v1/enrich     -> predict picklist values for a chunk of records
"""
import logging

import functions_framework

from llm import generate_json
from masking import mask_pii
from prompts import ENRICH_SYSTEM_PROMPT, SUMMARY_SYSTEM_PROMPT

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

# In production this lives in Firestore/BigQuery; in-memory keeps the showcase self-contained.
_TAXONOMY: dict[str, list[str]] = {}


@functions_framework.http
def main_handler(request):
    routes = {
        "/api/v1/summarize": summarize,
        "/api/v1/taxonomy": store_taxonomy,
        "/api/v1/enrich": enrich,
    }
    handler = routes.get(request.path)
    if request.path in ("/", "/health"):
        return {"status": "ok"}, 200
    if handler is None or request.method != "POST":
        return {"error": "not found"}, 404
    try:
        return handler(request.get_json(silent=True) or {}), 200
    except ValueError as exc:
        return {"error": str(exc)}, 400
    except Exception:  # noqa: BLE001 - never leak internals to the caller
        log.exception("Unhandled error on %s", request.path)
        return {"error": "internal error"}, 500


def summarize(body: dict) -> dict:
    context = body.get("context") or {}
    text = "\n\n".join(
        filter(None, [context.get("subject"), context.get("description"), *context.get("emails", [])])
    )
    if not text:
        raise ValueError("context is empty")
    if body.get("redact", True):
        text = mask_pii(text)

    result = generate_json(
        system_prompt=SUMMARY_SYSTEM_PROMPT,
        user_content=text[:200_000],
        schema={"type": "OBJECT", "properties": {"summary": {"type": "ARRAY", "items": {"type": "STRING"}}}},
    )
    return {"summary": result.get("summary", [])[:8]}


def store_taxonomy(body: dict) -> dict:
    reasons = body.get("reasons")
    if not isinstance(reasons, dict) or not reasons:
        raise ValueError("reasons must be a non-empty object")
    _TAXONOMY.clear()
    _TAXONOMY.update({k: sorted(v) for k, v in reasons.items()})
    return {"status": "ok", "reasons": len(_TAXONOMY)}


def enrich(body: dict) -> dict:
    if not _TAXONOMY:
        raise ValueError("taxonomy not synced - refusing to predict")
    predictions = []
    for record in body.get("records", []):
        notes = mask_pii(record.get("notes") or "")
        result = generate_json(
            system_prompt=ENRICH_SYSTEM_PROMPT.format(taxonomy=_TAXONOMY),
            user_content=notes,
            schema={
                "type": "OBJECT",
                "properties": {
                    "reason": {"type": "STRING", "enum": list(_TAXONOMY.keys())},
                    "subReason": {"type": "STRING"},
                    "confidence": {"type": "STRING", "enum": ["HIGH", "MEDIUM", "LOW"]},
                },
            },
        )
        reason, sub = result.get("reason"), result.get("subReason")
        if reason not in _TAXONOMY or sub not in _TAXONOMY[reason]:
            result["confidence"] = "LOW"  # server-side guardrail mirrors the Apex check
        predictions.append({"id": record.get("id"), **result})
    return {"predictions": predictions}
