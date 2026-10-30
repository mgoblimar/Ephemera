from fastapi import Request, UploadFile
from PIL import Image

from app.config import Settings
from app.image_store import ImageStore
from app.imaging import load_upload
from app.providers import Providers


def settings(request: Request) -> Settings:
    return request.app.state.settings


def providers(request: Request) -> Providers:
    return request.app.state.providers


def image_store(request: Request) -> ImageStore:
    return request.app.state.image_store


async def read_image_upload(
    upload: UploadFile, config: Settings, keep_alpha: bool = False, max_side: int | None = None
) -> Image.Image:
    # Read one byte past the limit so oversized files are rejected without buffering them fully.
    data = await upload.read(config.max_upload_bytes + 1)
    side = config.max_image_side if max_side is None else max_side
    return load_upload(data, config.max_upload_bytes, side, keep_alpha=keep_alpha)
