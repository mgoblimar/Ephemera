"""Segmentation and cutout endpoints (SAM 3.1)."""

import base64
from typing import Annotated, Any

import numpy as np
from fastapi import APIRouter, Depends, File, UploadFile
from pydantic import BaseModel, Field

from app.config import Settings
from app.envelope import ApiError, ok
from app.image_store import ImageStore
from app.imaging import (
    CutSize,
    CutStyle,
    apply_cut_style,
    dominant_palette,
    jpeg_bytes,
    mask_area_fraction,
    mask_bbox,
    mask_preview_png,
    png_bytes,
)
from app.providers import Providers
from app.providers.base import PointPrompt
from app.routes import deps

router = APIRouter(prefix="", tags=["segment"])

# Masks smaller than this fraction of the photo are treated as noise.
MIN_MASK_AREA_FRACTION = 0.01
MAX_POINTS = 10
MAX_MASKS_PER_CUTOUT = 20


class PointIn(BaseModel):
    x: float = Field(ge=0)
    y: float = Field(ge=0)
    positive: bool = True


class PointSegmentRequest(BaseModel):
    image_id: str = Field(min_length=1, max_length=64)
    points: list[PointIn] = Field(min_length=1, max_length=MAX_POINTS)


class CutoutRequest(BaseModel):
    image_id: str = Field(min_length=1, max_length=64)
    mask_ids: list[str] = Field(min_length=1, max_length=MAX_MASKS_PER_CUTOUT)
    cut_style: CutStyle = "tight"
    cut_size: CutSize = "m"


def _b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def _mask_json(mask_id: str, alpha: np.ndarray, score: float) -> dict[str, Any]:
    x, y, w, h = mask_bbox(alpha) or (0, 0, 0, 0)
    return {"id": mask_id, "bbox": [x, y, w, h], "score": round(score, 3), "preview_png": _b64(mask_preview_png(alpha))}


@router.post("/segment/auto")
async def segment_auto(
    image: Annotated[UploadFile, File()],
    config: Annotated[Settings, Depends(deps.settings)],
    models: Annotated[Providers, Depends(deps.providers)],
    store: Annotated[ImageStore, Depends(deps.image_store)],
) -> dict[str, Any]:
    photo = await deps.read_image_upload(image, config)
    masks = [m for m in models.segmentation.auto_masks(photo) if mask_area_fraction(m.alpha) >= MIN_MASK_AREA_FRACTION]
    image_id = store.put(photo)
    mask_ids = store.add_masks(image_id, [m.alpha for m in masks])
    width, height = photo.size
    return ok(
        {
            "image_id": image_id,
            "width": width,
            "height": height,
            # The upright, downscaled photo the masks refer to, so the app's overlay always lines up.
            "photo_jpeg": _b64(jpeg_bytes(photo)),
            "masks": [_mask_json(mid, m.alpha, m.score) for mid, m in zip(mask_ids, masks, strict=True)],
        }
    )


@router.post("/segment/point")
def segment_point(
    body: PointSegmentRequest,
    models: Annotated[Providers, Depends(deps.providers)],
    store: Annotated[ImageStore, Depends(deps.image_store)],
) -> dict[str, Any]:
    entry = store.get(body.image_id)
    width, height = entry.image.size
    if any(p.x >= width or p.y >= height for p in body.points):
        raise ApiError(422, "point_out_of_bounds", "Tap points must be inside the photo.")
    mask = models.segmentation.point_mask(entry.image, [PointPrompt(p.x, p.y, p.positive) for p in body.points])
    if mask_bbox(mask.alpha) is None:
        raise ApiError(422, "empty_mask", "Nothing found at that spot. Try tapping closer to the item.")
    (mask_id,) = store.add_masks(body.image_id, [mask.alpha])
    return ok({"mask": _mask_json(mask_id, mask.alpha, mask.score)})


@router.post("/cutout")
def cutout(body: CutoutRequest, store: Annotated[ImageStore, Depends(deps.image_store)]) -> dict[str, Any]:
    entry = store.get(body.image_id)
    unknown = [mid for mid in body.mask_ids if mid not in entry.masks]
    if unknown:
        raise ApiError(404, "mask_not_found", f"Unknown mask ids: {', '.join(unknown)}")

    scraps = []
    for mask_id in body.mask_ids:
        scrap = apply_cut_style(entry.image, entry.masks[mask_id], body.cut_style, body.cut_size)
        scraps.append(
            {
                "mask_id": mask_id,
                "png_base64": _b64(png_bytes(scrap)),
                "width": scrap.width,
                "height": scrap.height,
                "palette": dominant_palette(scrap),
            }
        )
    return ok({"scraps": scraps})
