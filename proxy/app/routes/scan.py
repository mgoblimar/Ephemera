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
from app.imaging import CutSize, CutStyle, apply_cut_style, border_px, dominant_palette, jpeg_bytes, png_bytes
from app.providers import Providers
from app.providers.base import PixelBox
from app.providers.sam import MAX_OBJECTS_PER_REQUEST
from app.routes import deps

router = APIRouter(prefix="/scan", tags=["scan"])

THUMB_SIDE = 256
MAX_PIECES_PER_CUT = 64  # cut in batches of 16, one SAM request each


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
                {
                    "id": piece_id,
                    "label": item.label,
                    "box": [item.box.left, item.box.top, item.box.right - item.box.left, item.box.bottom - item.box.top],
                    "thumb_jpeg": _thumb(photo, item.box),
                }
                for piece_id, item in zip(piece_ids, items, strict=True)
            ],
        }
    )


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
                missed.append(ref.model_dump())
                continue
            scraps.append(_scrap_json(ref, label, piece, cell, mask.alpha, body.cut_style, body.cut_size))
    return ok({"scraps": scraps, "missed": missed, "sam_requests": len(batches)})


def _scrap_json(
    ref: PieceRef, label: str, piece: Piece, cell: SheetCell, sheet_alpha: np.ndarray, style: CutStyle, size: CutSize
) -> dict[str, Any]:
    r = cell.region
    scrap = apply_cut_style(
        piece.photo.crop((r.left, r.top, r.right, r.bottom)),
        mask_for_piece(sheet_alpha, cell),
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
