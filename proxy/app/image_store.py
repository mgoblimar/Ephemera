"""Short-lived in-memory store for uploaded photos and their masks.

Photos live only long enough to review masks and cut scraps, then expire.
Nothing is written to disk.
"""

import time
import uuid
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field, replace
from threading import Lock
from types import MappingProxyType

import numpy as np
from PIL import Image

from app.envelope import ApiError


@dataclass(frozen=True)
class StoredImage:
    image: Image.Image  # working copy the models see (max_image_side)
    created_at: float
    masks: Mapping[str, np.ndarray] = field(default_factory=lambda: MappingProxyType({}))
    original: Image.Image | None = None  # full-resolution upright photo, used for cutouts

    @property
    def full(self) -> Image.Image:
        return self.original or self.image


class ImageStore:
    def __init__(self, ttl_seconds: int, clock: Callable[[], float] = time.monotonic) -> None:
        self._ttl = ttl_seconds
        self._clock = clock
        self._entries: dict[str, StoredImage] = {}
        self._lock = Lock()

    def put(self, image: Image.Image, original: Image.Image | None = None) -> str:
        image_id = uuid.uuid4().hex
        with self._lock:
            self._evict_expired()
            self._entries[image_id] = StoredImage(image=image, created_at=self._clock(), original=original)
        return image_id

    def get(self, image_id: str) -> StoredImage:
        with self._lock:
            self._evict_expired()
            entry = self._entries.get(image_id)
        if entry is None:
            raise ApiError(404, "image_not_found", "Photo expired or unknown. Please capture it again.")
        return entry

    def add_masks(self, image_id: str, masks: list[np.ndarray]) -> list[str]:
        """Attach masks to a stored image and return their new ids."""
        new_ids = [uuid.uuid4().hex[:12] for _ in masks]
        with self._lock:
            entry = self._entries.get(image_id)
            if entry is None:
                raise ApiError(404, "image_not_found", "Photo expired or unknown. Please capture it again.")
            merged = {**entry.masks, **dict(zip(new_ids, masks, strict=True))}
            self._entries[image_id] = replace(entry, masks=MappingProxyType(merged))
        return new_ids

    def _evict_expired(self) -> None:
        now = self._clock()
        expired = [key for key, entry in self._entries.items() if now - entry.created_at > self._ttl]
        for key in expired:
            del self._entries[key]
