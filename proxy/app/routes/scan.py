"""Scan sessions: detect cheaply per photo, then cut only the chosen pieces.

/scan/detect runs item detection only (Muse Spark, ~₱0.01) and remembers the
pieces. /scan/cut packs up to 16 chosen pieces - from any number of photos - onto
one contact sheet, so SAM cuts them all in a single billed request.
"""

import base64
from typing import Annotated, Any

import numpy as np
from fastapi import APIRouter, Depends, File, UploadFile
from PIL import Image
from pydantic import BaseModel, Field

from app.config import Settings
from app.contact_sheet import Piece, SheetCell, build_sheet, mask_for_piece
from app.envelope import ApiError, ok
from app.image_store import ImageStore, StoredImage
from app.imaging import (
    ROUGH_SOLIDITY,
    CutSize,
    CutStyle,
    apply_cut_style,
    border_px,
    clean_mask,
    dominant_palette,
    jpeg_bytes,
    mask_solidity,
    png_bytes,
)
from app.providers import Providers
from app.providers.base import DetectedItem, PixelBox
from app.providers.sam import MAX_OBJECTS_PER_REQUEST
from app.routes import deps

router = APIRouter(prefix="/scan", tags=["scan"])

THUMB_SIDE = 256
MAX_PIECES_PER_CUT = 64  # cut in batches of 16, one SAM request each
MIN_ELEMENT_SIDE = 64  # original-photo pixels; thinner elements are blurry slivers
MIN_ELEMENT_AREA_FRACTION = 0.02  # of the parent piece's area


class PieceRef(BaseModel):
    image_id: str = Field(min_length=1, max_length=64)
    piece_id: str = Field(min_length=1, max_length=64)


class CutRequest(BaseModel):
    pieces: list[PieceRef] = Field(min_length=1, max_length=MAX_PIECES_PER_CUT)
    cut_style: CutStyle = "tight"
    cut_size: CutSize = "m"


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def _thumb(photo: Image.Image, box: PixelBox) -> str:
    crop = photo.crop((box.left, box.top, box.right, box.bottom))
    crop.thumbnail((THUMB_SIDE, THUMB_SIDE))
    return _b64(jpeg_bytes(crop, quality=80))


@router.post("/detect")
async def detect(
    image: Annotated[UploadFile, File()],
    config: Annotated[Settings, Depends(deps.settings)],
    models: Annotated[Providers, Depends(deps.providers)],
    store: Annotated[ImageStore, Depends(deps.image_store)],
) -> dict[str, Any]:
    original = await deps.read_image_upload(image, config, max_side=config.max_original_side)
    photo = original.copy()
    photo.thumbnail((config.max_image_side, config.max_image_side))
    items = models.segmentation.detect_items(photo)
    image_id = store.put(photo, original=original)
    piece_ids = store.add_pieces(image_id, items)
    return ok(
        {
            "image_id": image_id,
            "width": photo.width,
            "height": photo.height,
            "pieces": [
                _piece_json(piece_id, item, photo, item.box) for piece_id, item in zip(piece_ids, items, strict=True)
            ],
        }
    )


class SplitRequest(BaseModel):
    image_id: str = Field(min_length=1, max_length=64)
    piece_id: str = Field(min_length=1, max_length=64)


@router.post("/split")
def split(
    body: SplitRequest,
    config: Annotated[Settings, Depends(deps.settings)],
    models: Annotated[Providers, Depends(deps.providers)],
    store: Annotated[ImageStore, Depends(deps.image_store)],
) -> dict[str, Any]:
    """Find design elements (logos, lettering...) inside one piece, as new choosable pieces."""
    entry = store.get(body.image_id)
    parent = entry.pieces.get(body.piece_id)
    if parent is None:
        raise ApiError(404, "piece_not_found", "That piece is no longer available. Please scan the photo again.")

    whole = _to_original(entry, parent.box)
    close_up = entry.full.crop((whole.left, whole.top, whole.right, whole.bottom))
    model_view = close_up.copy()
    model_view.thumbnail((config.max_image_side, config.max_image_side))  # max detail for the model
    view_scale = close_up.width / model_view.width

    found = [(e.label, _offset(e.box, view_scale, whole)) for e in models.segmentation.detect_elements(model_view)]
    elements = [
        DetectedItem(label=label, box=_to_working(entry, box)) for label, box in found if _big_enough(box, whole)
    ]
    element_ids = store.add_pieces(body.image_id, elements)
    return ok(
        {
            "parent_id": body.piece_id,
            "pieces": [
                _piece_json(piece_id, item, entry.full, _to_original(entry, item.box))
                for piece_id, item in zip(element_ids, elements, strict=True)
            ],
        }
    )


def _big_enough(box: PixelBox, parent: PixelBox) -> bool:
    """Tiny elements (side text, small badges) cut out as blurry slivers, so they're not offered."""
    width, height = box.right - box.left, box.bottom - box.top
    parent_area = (parent.right - parent.left) * (parent.bottom - parent.top)
    return min(width, height) >= MIN_ELEMENT_SIDE and width * height >= MIN_ELEMENT_AREA_FRACTION * parent_area


def _offset(box: PixelBox, scale: float, origin: PixelBox) -> PixelBox:
    """A box from the model's view of a close-up, in full-photo pixels."""
    return PixelBox(
        left=origin.left + int(box.left * scale),
        top=origin.top + int(box.top * scale),
        right=origin.left + round(box.right * scale),
        bottom=origin.top + round(box.bottom * scale),
    )


def _to_working(entry: StoredImage, box: PixelBox) -> PixelBox:
    scale = entry.image.width / entry.full.width
    return PixelBox(
        left=int(box.left * scale),
        top=int(box.top * scale),
        right=max(int(box.left * scale) + 1, round(box.right * scale)),
        bottom=max(int(box.top * scale) + 1, round(box.bottom * scale)),
    )


def _piece_json(piece_id: str, item: DetectedItem, thumb_source: Image.Image, thumb_box: PixelBox) -> dict[str, Any]:
    b = item.box
    return {
        "id": piece_id,
        "label": item.label,
        "box": [b.left, b.top, b.right - b.left, b.bottom - b.top],
        "thumb_jpeg": _thumb(thumb_source, thumb_box),
    }


def _to_original(entry: StoredImage, box: PixelBox) -> PixelBox:
    scale = entry.full.width / entry.image.width
    return PixelBox(
        left=int(box.left * scale), top=int(box.top * scale), right=round(box.right * scale), bottom=round(box.bottom * scale)
    )


def _resolve(store: ImageStore, refs: list[PieceRef]) -> list[tuple[PieceRef, StoredImage, str, Piece]]:
    resolved = []
    for ref in refs:
        entry = store.get(ref.image_id)
        item = entry.pieces.get(ref.piece_id)
        if item is None:
            raise ApiError(404, "piece_not_found", "That piece is no longer available. Please scan the photo again.")
        resolved.append((ref, entry, item.label, Piece(photo=entry.full, box=_to_original(entry, item.box))))
    return resolved


@router.post("/cut")
def cut(
    body: CutRequest,
    models: Annotated[Providers, Depends(deps.providers)],
    store: Annotated[ImageStore, Depends(deps.image_store)],
) -> dict[str, Any]:
    resolved = _resolve(store, body.pieces)
    scraps: list[dict[str, Any]] = []
    missed: list[dict[str, str]] = []
    batches = [resolved[i : i + MAX_OBJECTS_PER_REQUEST] for i in range(0, len(resolved), MAX_OBJECTS_PER_REQUEST)]
    for batch in batches:
        sheet = build_sheet([piece for *_, piece in batch])
        masks = models.segmentation.segment_boxes(sheet.image, [cell.prompt_box for cell in sheet.cells])
        for (ref, _, label, piece), cell, mask in zip(batch, sheet.cells, masks, strict=True):
            if mask is None:
                missed.append({**ref.model_dump(), "reason": "not_found"})
                continue
            alpha = clean_mask(mask_for_piece(mask.alpha, cell))
            if mask_solidity(alpha) < ROUGH_SOLIDITY:
                # Half-hidden or torn pieces come back as fragments; don't save junk.
                missed.append({**ref.model_dump(), "reason": "rough"})
                continue
            scraps.append(_scrap_json(ref, label, piece, cell, alpha, body.cut_style, body.cut_size))
    return ok({"scraps": scraps, "missed": missed, "sam_requests": len(batches)})


def _scrap_json(
    ref: PieceRef, label: str, piece: Piece, cell: SheetCell, alpha: np.ndarray, style: CutStyle, size: CutSize
) -> dict[str, Any]:
    """`alpha` is the piece's mask over its region of the full-size photo."""
    r = cell.region
    scrap = apply_cut_style(
        piece.photo.crop((r.left, r.top, r.right, r.bottom)),
        alpha,
        style,
        size,
        border=border_px(size, piece.photo.size),
    )
    return {
        "image_id": ref.image_id,
        "piece_id": ref.piece_id,
        "label": label,
        "png_base64": _b64(png_bytes(scrap)),
        "width": scrap.width,
        "height": scrap.height,
        "palette": dominant_palette(scrap),
    }
