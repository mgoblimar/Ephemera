"""Scrap enrichment: OCR, tags and mood (Muse Spark) plus a locally computed palette."""

from dataclasses import asdict
from typing import Annotated, Any

from fastapi import APIRouter, Depends, File, UploadFile

from app.config import Settings
from app.envelope import ok
from app.imaging import dominant_palette
from app.providers import Providers
from app.routes import deps

router = APIRouter(tags=["enrich"])


@router.post("/enrich")
async def enrich(
    scrap: Annotated[UploadFile, File()],
    config: Annotated[Settings, Depends(deps.settings)],
    models: Annotated[Providers, Depends(deps.providers)],
) -> dict[str, Any]:
    image = await deps.read_image_upload(scrap, config, keep_alpha=True)
    result = asdict(models.vision.enrich(image))
    return ok({**result, "tags": list(result["tags"]), "mood": list(result["mood"]), "palette": dominant_palette(image)})
