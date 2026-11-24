"""PII masking applied before any text is sent to the LLM.

Production uses Google Cloud DLP (deidentify_content with reversible crypto tokens so summaries can be
re-identified for internal users). This regex fallback keeps the showcase runnable without DLP.
"""
import os
import re

_PATTERNS = [
    (re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+"), "[EMAIL]"),
    (re.compile(r"\+?\d[\d\s().-]{8,}\d"), "[PHONE]"),
    (re.compile(r"\b(?:\d[ -]*?){13,16}\b"), "[CARD]"),
]


def mask_pii(text: str) -> str:
    if os.getenv("USE_CLOUD_DLP") == "true":
        return _mask_with_dlp(text)
    for pattern, token in _PATTERNS:
        text = pattern.sub(token, text)
    return text


def _mask_with_dlp(text: str) -> str:
    from google.cloud import dlp_v2

    client = dlp_v2.DlpServiceClient()
    response = client.deidentify_content(
        request={
            "parent": f"projects/{os.environ['GCP_PROJECT']}/locations/global",
            "inspect_config": {
                "info_types": [{"name": n} for n in ("EMAIL_ADDRESS", "PHONE_NUMBER", "PERSON_NAME", "CREDIT_CARD_NUMBER")]
            },
            "deidentify_config": {
                "info_type_transformations": {
                    "transformations": [{"primitive_transformation": {"replace_with_info_type_config": {}}}]
                }
            },
            "item": {"value": text},
        }
    )
    return response.item.value
