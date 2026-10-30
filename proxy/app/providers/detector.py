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
MIN_BOX_FRACTION = 0.01  # drop boxes smaller than 1% of the photo's width or height

# Boxes are asked for in pixels of the image as sent, with its size stated (a 0-1000 grid was up
# to 3% off on portrait photos). Even so, Spark puts boxes too LOW: on known rectangles (Oct 31) the
# top and bottom came back +28..+57 px (once +89) at 1536 px, in ~28 px steps (its patch grid?),
# while left/right were within a few px. Real 16:9 tablet scans showed the same: tops started
# below the piece and bottoms ran into its shadow. So y is shifted back up by about one step.
Y_BIAS_FRACTION = 0.02  # of the image's longer side (~31 px at 1536)
SYSTEM_PROMPT = "You locate physical objects in photos precisely and reply with JSON only."
DETECT_PROMPT = """This photo is {width}x{height} pixels and shows junk-journal materials.
List every separate piece a journaler could peel off or cut out and use on its own:
- A sheet of stickers or labels: list EACH sticker separately, never the whole sheet or its backing card.
- Loose items (tickets, wrappers, receipts, flowers, tape, paper scraps): list each item.
- Only pieces you can see whole: skip anything partly hidden behind other things, cut off by the
  photo's edge, or buried in a pile or shop display.
- Ignore the table or background, hands, shadows, and clear plastic sleeves holding the items.
For each piece give:
- "label": one of {labels}
- "box": [x1, y1, x2, y2] in pixels, where (0,0) is the top-left of the photo and ({width},{height})
  the bottom-right. Hug the piece's own edge; leave out its backing card, sleeve and shadow.
List at most {limit} pieces, largest first.
Reply with only: {{"items": [{{"label": "...", "box": [x1, y1, x2, y2]}}]}}"""

# Splitting one scrap into the printed design elements a journaler would cut out on their own.
ELEMENT_TYPES = ("logo", "lettering", "illustration", "badge", "character", "pattern", "photo", "other")
ELEMENT_PROMPT = """This is a {width}x{height} pixel close-up of one junk-journal scrap (a wrapper, ticket, box, bag, label, etc.).
The crop may show a little of the table, its shadow or neighbouring things around the scrap: ignore
those and look only at what is printed on the scrap itself.
List the printed design elements on it that a journaler could cut out and use on their own as a
sticker: logos, words or lettering, illustrations, badges or labels, characters, decorative motifs.
- Each element is one self-contained printed shape with a clear edge against what surrounds it;
  keep a logo with its own outline/frame.
- Include the main illustration or product picture when it stands out clearly from its background.
- Skip plain background, fine print, paragraphs of small text, barcodes and nutrition facts,
  see-through windows or holes, tiny marks, and pictures that blend into busy surroundings.
For each element give:
- "label": one of {labels}
- "box": [x1, y1, x2, y2] in pixels, where (0,0) is the top-left of this image and ({width},{height})
  the bottom-right. Hug the element's own edge.
List at most {limit} elements, most eye-catching first.
Reply with only: {{"items": [{{"label": "...", "box": [x1, y1, x2, y2]}}]}}"""
MAX_ELEMENTS = 8


class SparkItemDetector:
    def __init__(self, transport: VisionTransport) -> None:
        self._transport = transport

    def detect(self, image: Image.Image) -> list[DetectedItem]:
        prompt = _prompt(DETECT_PROMPT, image.size, SCRAP_TYPES, MAX_OBJECTS_PER_REQUEST)
        return parse_detections(self._transport(SYSTEM_PROMPT, prompt, image), image.size)

    def detect_elements(self, scrap: Image.Image) -> list[DetectedItem]:
        """Design elements inside one scrap's crop; boxes are in the crop's pixels."""
        prompt = _prompt(ELEMENT_PROMPT, scrap.size, ELEMENT_TYPES, MAX_ELEMENTS)
        reply = self._transport(SYSTEM_PROMPT, prompt, scrap)
        return parse_detections(reply, scrap.size, allowed=ELEMENT_TYPES)[:MAX_ELEMENTS]


def _prompt(template: str, size: tuple[int, int], labels: tuple[str, ...], limit: int) -> str:
    width, height = size
    return template.format(width=width, height=height, labels=", ".join(labels), limit=limit)


def parse_detections(
    reply: str, size: tuple[int, int], allowed: tuple[str, ...] = SCRAP_TYPES
) -> list[DetectedItem]:
    """Parse the model's JSON (boxes in pixels), clamp boxes to the image and drop anything malformed."""
    payload = extract_json(reply)
    if payload is None:
        logger.warning("Detector reply was not JSON: %.200s", reply)
        return []
    raw_items = payload.get("items", []) if isinstance(payload, dict) else []
    items = [item for raw in raw_items if (item := _to_item(raw, size, allowed)) is not None]
    return items[:MAX_OBJECTS_PER_REQUEST]


def extract_json(reply: str) -> object | None:
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
    y_bias = Y_BIAS_FRACTION * max(width, height)
    x1, x2 = (round(max(0.0, min(float(v), width))) for v in (box[0], box[2]))
    y1, y2 = (round(max(0.0, min(float(v) - y_bias, height))) for v in (box[1], box[3]))
    left, right = sorted((x1, x2))
    top, bottom = sorted((y1, y2))
    if right - left < MIN_BOX_FRACTION * width or bottom - top < MIN_BOX_FRACTION * height:
        return None
    label = raw.get("label")
    return DetectedItem(
        label=label if label in allowed else "other",
        box=PixelBox(left=left, top=top, right=right, bottom=bottom),
    )
