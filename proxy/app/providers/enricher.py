"""Muse Spark enrichment: read a scrap's text and context (SPEC 4.3).

Returns OCR text, dates/places/times, tags, mood, a one-line description, a journal
prompt and two caption ideas (all from the same single call).
The palette is computed locally (imaging.dominant_palette), not by the model.
"""

import logging

from PIL import Image

from app.providers.base import Enrichment
from app.providers.detector import ELEMENT_TYPES, SCRAP_TYPES, VisionTransport, extract_json

logger = logging.getLogger(__name__)

KNOWN_TYPES = frozenset(SCRAP_TYPES) | frozenset(ELEMENT_TYPES)
ENTITY_KEYS = ("date", "time", "place", "brand", "price")
MAX_TAGS = 8
MAX_MOODS = 4
MAX_TEXT = 600
MAX_CAPTIONS = 2
MAX_CAPTION_CHARS = 60
MAX_PROMPT_CHARS = 160

SYSTEM_PROMPT = "You catalogue junk-journal scraps precisely and reply with JSON only."
USER_PROMPT = f"""This is one cut-out scrap from someone's junk journal (ticket, receipt, wrapper, sticker, note, flower...).
Read it and describe it for their archive. Reply with only this JSON:
{{"type": one of {", ".join(sorted(KNOWN_TYPES))},
 "ocr_text": all readable text, in reading order ("" if none),
 "entities": {{"date": "YYYY-MM-DD", "time": "HH:MM", "place": "...", "brand": "...", "price": "..."}} (only keys you can read),
 "tags": up to {MAX_TAGS} short lowercase tags for searching (objects, colours, themes, e.g. "coffee", "yellow", "travel"),
 "mood": up to {MAX_MOODS} lowercase mood words (e.g. "cozy", "nostalgic", "playful"),
 "description": one short sentence about what it is and how it looks,
 "journal_prompt": one short, warm question inviting them to write about the memory behind it (e.g. "Who did you share this coffee with?"),
 "captions": {MAX_CAPTIONS} short handwritten-style captions (at most 6 words each) that could sit next to it on a page}}"""


class SparkEnricher:
    def __init__(self, transport: VisionTransport) -> None:
        self._transport = transport

    def enrich(self, scrap: Image.Image) -> Enrichment:
        reply = self._transport(SYSTEM_PROMPT, USER_PROMPT, on_white(scrap))
        return parse_enrichment(reply)


def on_white(image: Image.Image) -> Image.Image:
    """Flatten transparency onto white; transparent pixels would turn black in a JPEG."""
    if image.mode != "RGBA":
        return image.convert("RGB")
    background = Image.new("RGB", image.size, (255, 255, 255))
    background.paste(image, mask=image.getchannel("A"))
    return background


def parse_enrichment(reply: str) -> Enrichment:
    """Tolerant parse: anything missing or malformed becomes an empty value."""
    payload = extract_json(reply)
    if not isinstance(payload, dict):
        logger.warning("Enrichment reply was not JSON: %.200s", reply)
        payload = {}
    kind = payload.get("type")
    entities = payload.get("entities") if isinstance(payload.get("entities"), dict) else {}
    return Enrichment(
        type=kind if kind in KNOWN_TYPES else "other",
        ocr_text=_text(payload.get("ocr_text"))[:MAX_TEXT],
        entities={k: _text(v) for k, v in entities.items() if k in ENTITY_KEYS and _text(v)},
        tags=_words(payload.get("tags"), MAX_TAGS),
        mood=_words(payload.get("mood"), MAX_MOODS),
        description=_text(payload.get("description"))[:MAX_TEXT],
        journal_prompt=_text(payload.get("journal_prompt"))[:MAX_PROMPT_CHARS],
        captions=tuple(
            c[:MAX_CAPTION_CHARS] for c in (_text(v) for v in _list(payload.get("captions"))) if c
        )[:MAX_CAPTIONS],
    )


def _text(value: object) -> str:
    return value.strip() if isinstance(value, str) else ""


def _list(value: object) -> list[object]:
    return value if isinstance(value, list) else []


def _words(value: object, limit: int) -> tuple[str, ...]:
    if not isinstance(value, list):
        return ()
    words = [w.strip().lower() for w in value if isinstance(w, str) and w.strip()]
    return tuple(dict.fromkeys(words))[:limit]
