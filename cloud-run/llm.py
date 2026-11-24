"""Thin wrapper around Gemini on Vertex AI with structured (JSON) output."""
import json
import os
import random

from google import genai
from google.genai import types

_REGIONS = os.getenv("VERTEX_REGIONS", "us-central1,us-east4,us-west1").split(",")
_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
_PROJECT = os.getenv("GCP_PROJECT")


def generate_json(system_prompt: str, user_content: str, schema: dict) -> dict:
    """Calls Gemini and returns parsed JSON.

    A random region is chosen per call: Vertex quotas are regional, so spreading load avoids 429s
    during bursts. Low temperature + response schema keep output deterministic and parseable.
    """
    client = genai.Client(vertexai=True, project=_PROJECT, location=random.choice(_REGIONS))
    response = client.models.generate_content(
        model=_MODEL,
        contents=user_content,
        config=types.GenerateContentConfig(
            system_instruction=system_prompt,
            temperature=0.2,
            max_output_tokens=1024,
            response_mime_type="application/json",
            response_schema=schema,
        ),
    )
    return json.loads(response.text or "{}")
