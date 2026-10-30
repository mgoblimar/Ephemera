"""SAM 3.1 over the Responses API: box, point and concept prompts.

SAM returns one text line per image: for each object a box (source pixels) and a
binary mask raster covering just that box at lower resolution. We decode the
raster, scale it up to the box and paste it into a full-size alpha mask.
"""

import logging
import math
import re
from collections.abc import Callable, Sequence
from dataclasses import dataclass, replace

import numpy as np
from meta_sam_parser import (
    CompletedOutcome,
    FramePrompt,
    PromptBox,
    PromptObject,
    PromptPoint,
    SegmentationMask,
    SegmentationMaskRecord,
    build_object_prompt,
    decode_mask_to_raster,
    image_segmentation_format,
)

# Internal one-pass decoder; requirements.txt pins meta-sam-parser so this stays put.
from meta_sam_parser._mask_codec import _decode_raster
from PIL import Image

from app.providers.base import Mask, PixelBox, PointPrompt

logger = logging.getLogger(__name__)

# One object record: "<id><|box;x1=..;y1=..;x2=..;y2=..;w=..;h=..[;c=..]|><|mask;x=0;y=0;data=H,W,payload[;c=..]|>".
# Fields are ";"-separated, so payloads never contain ";" or "|".
_RECORD_PATTERN = re.compile(r"(?P<id>\d+)<\|box;(?P<box>[^|]*)\|><\|mask;(?P<mask>[^|]*)\|>")
_MASK_DATA_PATTERN = re.compile(r"([0-9]+),([0-9]+),([!~].+)")

# Sends (prompt text, image) to SAM and returns the response's output_text.
SamTransport = Callable[[str, Image.Image], str]

MAX_OBJECTS_PER_REQUEST = 16  # documented SAM limit for box/point prompts
DEFAULT_SCORE = 1.0  # used when the response carries no confidence



class SamClient:
    def __init__(self, transport: SamTransport) -> None:
        self._transport = transport

    def segment_boxes(self, image: Image.Image, boxes: Sequence[PixelBox]) -> list[Mask | None]:
        """One mask per box, in order (None where SAM found nothing). Max 16 boxes."""
        if not boxes:
            return []
        if len(boxes) > MAX_OBJECTS_PER_REQUEST:
            raise ValueError(f"SAM accepts at most {MAX_OBJECTS_PER_REQUEST} objects per request.")
        objects = [
            PromptObject(id=index, prompts=[FramePrompt(frame=0, box=PromptBox(b.left, b.top, b.right, b.bottom))])
            for index, b in enumerate(boxes)
        ]
        by_id = self._run(image, build_object_prompt(size=image.size, objects=objects))
        return [by_id.get(str(index)) for index in range(len(boxes))]

    def segment_points(self, image: Image.Image, points: Sequence[PointPrompt]) -> Mask | None:
        prompt_points = [
            PromptPoint(round(p.x), round(p.y), "positive" if p.positive else "negative") for p in points
        ]
        objects = [PromptObject(id=0, prompts=[FramePrompt(frame=0, points=prompt_points)])]
        return self._run(image, build_object_prompt(size=image.size, objects=objects)).get("0")

    def segment_concept(self, image: Image.Image, phrase: str) -> list[Mask]:
        """Every instance of a short noun phrase, e.g. "ticket"."""
        return list(self._run(image, phrase).values())

    def _run(self, image: Image.Image, prompt: str) -> dict[str, Mask]:
        return parse_sam_output(self._transport(prompt, image), image.size)


@dataclass(frozen=True)
class _RawMask:
    object_id: str
    bounds: PixelBox
    mask: SegmentationMask
    confidence: float | None
    source_size: tuple[int, int] | None = None  # (w, h) SAM says its coordinates refer to


def parse_sam_output(output_text: str, size: tuple[int, int]) -> dict[str, Mask]:
    """Map object id -> full-size mask for a single-image SAM response."""
    records = _fast_records(output_text)
    if not records and "<|mask" in output_text:
        records = _library_records(output_text)  # unexpected format: let Meta's parser handle it
    masks: dict[str, Mask] = {}
    for record in (_rescale(r, size) for r in records):
        raster = _decode_once(record.mask)
        if raster is None:
            logger.warning("Skipping undecodable SAM mask for object %s", record.object_id)
            continue
        masks[record.object_id] = Mask(alpha=_place_mask(record, raster, size), score=record.confidence or DEFAULT_SCORE)
    return masks


def _fast_records(output_text: str) -> list[_RawMask]:
    """Read box+mask records directly (same grammar as meta_sam_parser, see module docstring).

    Meta's parser decodes and re-encodes every mask to validate it, and we'd decode
    again after; with its pure-Python codec that was ~4x the work, seconds per photo.
    """
    records: list[_RawMask] = []
    for match in _RECORD_PATTERN.finditer(output_text):
        box, mask = _fields(match.group("box")), _fields(match.group("mask"))
        data = _MASK_DATA_PATTERN.fullmatch(mask.get("data", ""))
        try:
            left, top, right, bottom = (int(box[k]) for k in ("x1", "y1", "x2", "y2"))
        except (KeyError, ValueError):
            continue
        if data is None or right < left or bottom < top:
            continue
        payload = data.group(3)
        records.append(
            _RawMask(
                object_id=match.group("id"),
                bounds=PixelBox(left=left, top=top, right=right + 1, bottom=bottom + 1),  # x2/y2 are inclusive
                mask=SegmentationMask(
                    encoding="lossless" if payload.startswith("~") else "one_bit",
                    payload=payload,
                    width=int(data.group(2)),
                    height=int(data.group(1)),
                ),
                confidence=_confidence(mask.get("c") or box.get("c")),
                source_size=_int_pair(box.get("w"), box.get("h")),
            )
        )
    return records


def _int_pair(a: str | None, b: str | None) -> tuple[int, int] | None:
    try:
        return (int(a), int(b)) if a and b else None
    except ValueError:
        return None


def _rescale(record: _RawMask, size: tuple[int, int]) -> _RawMask:
    """SAM may work on a downscaled copy of large images; map its coordinates back to ours."""
    if record.source_size is None or record.source_size == size:
        return record
    logger.warning("SAM coordinates are for %s, our image is %s; rescaling", record.source_size, size)
    sx, sy = size[0] / record.source_size[0], size[1] / record.source_size[1]
    b = record.bounds
    scaled = PixelBox(
        left=int(b.left * sx), top=int(b.top * sy), right=math.ceil(b.right * sx), bottom=math.ceil(b.bottom * sy)
    )
    return replace(record, bounds=scaled, source_size=size)


def _library_records(output_text: str) -> list[_RawMask]:
    parser = image_segmentation_format().create_parser()
    parser.push(output_text)
    result = parser.finish(CompletedOutcome()).result
    return [
        _RawMask(
            object_id=r.object_id,
            bounds=PixelBox(int(r.bounds.left), int(r.bounds.top), int(r.bounds.right), int(r.bounds.bottom)),
            mask=r.mask,
            confidence=r.confidence,
        )
        for r in result.records
        if isinstance(r, SegmentationMaskRecord)
    ]


def _fields(body: str) -> dict[str, str]:
    pairs = (part.strip().partition("=") for part in body.split(";"))
    return {key.strip(): value.strip() for key, _, value in pairs if key.strip()}


def _confidence(text: str | None) -> float | None:
    try:
        value = float(text) if text is not None else None
    except ValueError:
        return None
    return value if value is not None and 0.0 <= value <= 1.0 else None


def _decode_once(mask: SegmentationMask) -> bytes | None:
    try:
        if mask.encoding == "one_bit":
            # Single decoding pass; the public decoder also re-encodes to check canonical form.
            return _decode_raster(mask.payload, mask.width, mask.height)
        return decode_mask_to_raster(mask)
    except Exception:  # noqa: BLE001 - any codec failure just drops this one mask
        return None


def _place_mask(record: _RawMask, raster_bytes: bytes, size: tuple[int, int]) -> np.ndarray:
    width, height = size
    raster = np.frombuffer(raster_bytes, dtype=np.uint8)
    small = Image.fromarray((raster.reshape(record.mask.height, record.mask.width) * 255).astype(np.uint8), "L")

    left, top = record.bounds.left, record.bounds.top
    right, bottom = min(record.bounds.right, width), min(record.bounds.bottom, height)
    alpha = np.zeros((height, width), dtype=np.float32)
    if right <= left or bottom <= top:
        return alpha
    # Bilinear upscaling softens the staircase edges of the low-resolution raster.
    scaled = small.resize((right - left, bottom - top), Image.Resampling.BILINEAR)
    alpha[top:bottom, left:right] = np.asarray(scaled, dtype=np.float32) / 255
    return alpha


def mask_iou(a: np.ndarray, b: np.ndarray) -> float:
    on_a, on_b = a > 0.5, b > 0.5
    union = np.logical_or(on_a, on_b).sum()
    return float(np.logical_and(on_a, on_b).sum() / union) if union else 0.0
