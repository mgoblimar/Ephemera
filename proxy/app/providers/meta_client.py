"""Shared plumbing for calls to the Meta Model API (OpenAI-compatible)."""

import base64
import logging
import time
from collections.abc import Callable
from typing import Any, TypeVar

from openai import APIError, APITimeoutError, OpenAI
from PIL import Image

from app.config import Settings
from app.envelope import ApiError
from app.imaging import jpeg_bytes

logger = logging.getLogger(__name__)

REQUEST_TIMEOUT_SECONDS = 60.0
MAX_RETRIES = 2  # the SDK retries connection errors, 429s and 5xx with backoff

T = TypeVar("T")


def build_client(settings: Settings) -> OpenAI:
    return OpenAI(
        api_key=settings.meta_api_key,
        base_url=settings.meta_api_base_url,
        timeout=REQUEST_TIMEOUT_SECONDS,
        max_retries=MAX_RETRIES,
    )


def image_data_url(image: Image.Image) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(jpeg_bytes(image)).decode("ascii")


def call_model(what: str, request: Callable[[], T]) -> T:
    """Run one model request, turning SDK failures into a user-facing ApiError."""
    started = time.perf_counter()
    try:
        result = request()
        logger.info("%s took %.1fs", what, time.perf_counter() - started)
        return result
    except APITimeoutError as exc:
        logger.warning("%s timed out: %s", what, exc)
        raise ApiError(504, "model_timeout", "The AI took too long to answer. Please try again.") from exc
    except APIError as exc:
        logger.warning("%s failed: %s", what, exc)
        raise ApiError(502, "model_error", "The AI service had a problem. Please try again.") from exc


def log_usage(what: str, model: str, usage: Any) -> None:
    logger.info("%s via %s usage=%s", what, model, usage)
