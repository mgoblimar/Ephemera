"""Muse Image (generated decorations) plus a free offline stand-in."""

import base64
import io

import httpx
from openai import OpenAI
from PIL import Image, ImageDraw, UnidentifiedImageError

from app.config import Settings
from app.envelope import ApiError
from app.providers.meta_client import call_model, log_usage

IMAGE_SIZE = "1024x1024"
DOWNLOAD_TIMEOUT_SECONDS = 30.0


class MuseImageGenerator:
    def __init__(self, client: OpenAI, settings: Settings) -> None:
        self._client = client
        self._model = settings.image_model

    def generate(self, prompt: str) -> Image.Image:
        response = call_model(
            "Image generation",
            lambda: self._client.images.generate(
                model=self._model, prompt=prompt, n=1, size=IMAGE_SIZE, response_format="b64_json"
            ),
        )
        log_usage("Image generation", self._model, getattr(response, "usage", None))
        if not response.data:
            raise ApiError(502, "no_image", "The image model returned nothing (it may have been filtered). Try again.")
        first = response.data[0]
        if first.b64_json:
            data = base64.b64decode(first.b64_json)
        elif first.url:
            data = httpx.get(first.url, timeout=DOWNLOAD_TIMEOUT_SECONDS).raise_for_status().content
        else:
            raise ApiError(502, "no_image", "The image model returned nothing. Try again.")
        try:
            return Image.open(io.BytesIO(data)).convert("RGB")
        except (UnidentifiedImageError, OSError) as exc:
            raise ApiError(502, "bad_image", "The image model sent an unreadable picture. Try again.") from exc


class MockImageGenerator:
    """A terracotta stamp with a cream centre on white, so the cut-out path runs for free."""

    def generate(self, prompt: str) -> Image.Image:
        image = Image.new("RGB", (512, 512), "white")
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((96, 128, 416, 384), radius=18, fill=(181, 96, 63))
        draw.rectangle((140, 172, 372, 340), fill=(244, 236, 221))  # enclosed white-ish: must stay
        return image
