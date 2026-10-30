"""Muse Spark item detection (auto-detect Plan A): find each scrap's box and type.

SAM 3.1 has no "segment everything" mode, so a vision model first lists the items
on the desk; their boxes then go to SAM as box prompts in a single request.
"""

import json
import logging
import re
from collections.abc import Callable

from PIL import Image

from app.providers.base import DetectedItem, PixelBox
from app.providers.sam import MAX_OBJECTS_PER_REQUEST

logger = logging.getLogger(__name__)

# Sends (system prompt, user text, image) to the vision model and returns its text reply.
VisionTransport = Callable[[str, str, Image.Image], str]

SCRAP_TYPES = (
    "ticket",
    "receipt",
    "wrapper",
    "botanical",
    "tape",
    "paper",
    "sticker",
    "note",
    "photo",
    "label",
    "other",
)
COORDINATE_SCALE = 1000  # the model reports boxes on a 0-1000 grid, independent of photo size
MIN_BOX_FRACTION = 0.01  # drop boxes smaller than 1% of the photo's width or height

SYSTEM_PROMPT = "You locate physical objects in photos precisely and reply with JSON only."
USER_PROMPT = f"""This photo shows junk-journal materials.
List every separate piece a journaler could peel off or cut out and use on its own:
- A sheet of stickers or labels: list EACH sticker separately, never the whole sheet or its backing card.
- Loose items (tickets, wrappers, receipts, flowers, tape, paper scraps): list each item.
- Ignore the table or background, hands, and clear plastic sleeves holding the items.
For each piece give:
- "label": one of {", ".join(SCRAP_TYPES)}
- "box": [x1, y1, x2, y2], the tight bounding box on a 0-{COORDINATE_SCALE} grid where (0,0) is the top-left
  of the photo and ({COORDINATE_SCALE},{COORDINATE_SCALE}) the bottom-right.
List at most {MAX_OBJECTS_PER_REQUEST} pieces, largest first.
Reply with only: {{"items": [{{"label": "...", "box": [x1, y1, x2, y2]}}]}}"""

# Splitting one scrap into the printed design elements a journaler would cut out on their own.
ELEMENT_TYPES = ("logo", "lettering", "illustration", "badge", "character", "pattern", "photo", "other")
ELEMENT_PROMPT = f"""This is a close-up of one junk-journal scrap (a wrapper, ticket, box, bag, label, etc.).
List the printed design elements on it that a journaler could cut out and use on their own as a
sticker: logos, words or lettering, illustrations, badges or labels, characters, decorative motifs.
- Each element is one visually self-contained shape; keep a logo with its own outline/frame.
- Always include the main illustration or product picture if there is one, even when it is large.
- Skip plain background, fine print, paragraphs of small text, barcodes and nutrition facts.
For each element give:
- "label": one of {", ".join(ELEMENT_TYPES)}
- "box": [x1, y1, x2, y2], the tight bounding box on a 0-{COORDINATE_SCALE} grid where (0,0) is the
  top-left of this image and ({COORDINATE_SCALE},{COORDINATE_SCALE}) the bottom-right.
List at most 8 elements, most eye-catching first.
Reply with only: {{"items": [{{"label": "...", "box": [x1, y1, x2, y2]}}]}}"""
MAX_ELEMENTS = 8


class SparkItemDetector:
    def __init__(self, transport: VisionTransport) -> None:
        self._transport = transport

    def detect(self, image: Image.Image) -> list[DetectedItem]:
        reply = self._transport(SYSTEM_PROMPT, USER_PROMPT, image)
        return parse_detections(reply, image.size)

    def detect_elements(self, scrap: Image.Image) -> list[DetectedItem]:
        """Design elements inside one scrap's crop; boxes are in the crop's pixels."""
        reply = self._transport(SYSTEM_PROMPT, ELEMENT_PROMPT, scrap)
        return parse_detections(reply, scrap.size, allowed=ELEMENT_TYPES)[:MAX_ELEMENTS]


def parse_detections(
    reply: str, size: tuple[int, int], allowed: tuple[str, ...] = SCRAP_TYPES
) -> list[DetectedItem]:
    """Parse the model's JSON, scale boxes to pixels and drop anything malformed."""
    payload = _extract_json(reply)
    if payload is None:
        logger.warning("Detector reply was not JSON: %.200s", reply)
        return []
    raw_items = payload.get("items", []) if isinstance(payload, dict) else []
    items = [item for raw in raw_items if (item := _to_item(raw, size, allowed)) is not None]
    return items[:MAX_OBJECTS_PER_REQUEST]


def _extract_json(reply: str) -> object | None:
    """Accept bare JSON or JSON wrapped in a markdown code fence."""
    fenced = re.search(r"```(?:json)?\s*(.*?)```", reply, re.DOTALL)
    text = fenced.group(1) if fenced else reply
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end <= start:
        return None
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None


def _to_item(raw: object, size: tuple[int, int], allowed: tuple[str, ...]) -> DetectedItem | None:
    if not isinstance(raw, dict):
        return None
    box = raw.get("box")
    if not (isinstance(box, list) and len(box) == 4 and all(isinstance(v, int | float) for v in box)):
        return None
    width, height = size
    x1, y1, x2, y2 = (max(0.0, min(float(v), COORDINATE_SCALE)) / COORDINATE_SCALE for v in box)
    left, right = sorted((round(x1 * width), round(x2 * width)))
    top, bottom = sorted((round(y1 * height), round(y2 * height)))
    if right - left < MIN_BOX_FRACTION * width or bottom - top < MIN_BOX_FRACTION * height:
        return None
    label = raw.get("label")
    return DetectedItem(
        label=label if label in allowed else "other",
        box=PixelBox(left=left, top=top, right=right, bottom=bottom),
    )
