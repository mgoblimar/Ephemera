"""Day 1 check: does the hackathon key serve muse-wonder-1.0 with native tool calling?

Run from the proxy folder with META_API_KEY in proxy/.env:
    .venv/Scripts/python scripts/muse_tool_call_check.py

Makes two small requests (well under $0.01 of tokens) and prints a PASS/FAIL report.
"""

import json
import sys
import time
from pathlib import Path

from openai import OpenAI, OpenAIError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.config import Settings  # noqa: E402

SEARCH_ARCHIVE_TOOL = {
    "type": "function",
    "function": {
        "name": "search_archive",
        "description": "Search the user's archive of journal scraps by text, tags or type.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Free-text search over OCR text and tags."},
                "types": {"type": "array", "items": {"type": "string"}, "description": "Scrap types to include."},
                "limit": {"type": "integer", "default": 10},
            },
            "required": ["query"],
        },
    },
}

FAKE_RESULTS = [
    {"id": "scrap_1", "type": "receipt", "tags": ["coffee", "cafe"], "ocr_text": "Café Lumière 09:42"},
    {"id": "scrap_2", "type": "botanical", "tags": ["pressed flower", "brown"], "ocr_text": ""},
]


def main() -> int:
    settings = Settings()
    if not settings.meta_api_key:
        print("FAIL: META_API_KEY is not set. Add it to proxy/.env (see .env.example).")
        return 1

    client = OpenAI(api_key=settings.meta_api_key, base_url=settings.meta_api_base_url)
    model = settings.muse_wonder_model
    messages: list[dict] = [
        {"role": "system", "content": "You design junk-journal pages. Use the tools to find scraps before answering."},
        {"role": "user", "content": "Find scraps for the theme 'slow Sunday café morning, warm browns'."},
    ]
    print(f"Endpoint: {settings.meta_api_base_url}\nModel:    {model}\n")

    try:
        started = time.perf_counter()
        first = client.chat.completions.create(model=model, messages=messages, tools=[SEARCH_ARCHIVE_TOOL], tool_choice="auto")
        print(f"[1] responded in {time.perf_counter() - started:.1f}s, usage={first.usage}")
    except OpenAIError as exc:
        print(f"FAIL: first request errored: {type(exc).__name__}: {exc}")
        return 1

    reply = first.choices[0].message
    if not reply.tool_calls:
        print("FAIL: no tool_calls returned; the model answered in text instead:")
        print(reply.content)
        return 1

    call = reply.tool_calls[0]
    print(f"[1] tool call: {call.function.name}({call.function.arguments})")
    messages.append(reply.model_dump(exclude_none=True))
    messages.append({"role": "tool", "tool_call_id": call.id, "content": json.dumps(FAKE_RESULTS)})

    try:
        started = time.perf_counter()
        second = client.chat.completions.create(model=model, messages=messages, tools=[SEARCH_ARCHIVE_TOOL])
        print(f"[2] responded in {time.perf_counter() - started:.1f}s, usage={second.usage}")
    except OpenAIError as exc:
        print(f"FAIL: follow-up with tool result errored: {type(exc).__name__}: {exc}")
        return 1

    print(f"[2] final answer:\n{second.choices[0].message.content}\n")
    print("PASS: native tool calling works end to end.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
