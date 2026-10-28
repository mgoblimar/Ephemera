"""Provider interfaces. Each Meta model sits behind one of these, so the mock
and real implementations are interchangeable."""

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Protocol

import numpy as np
from PIL import Image


@dataclass(frozen=True)
class PointPrompt:
    x: float
    y: float
    positive: bool = True


@dataclass(frozen=True)
class Mask:
    alpha: np.ndarray  # (height, width) float32 in [0, 1]
    score: float


@dataclass(frozen=True)
class Enrichment:
    type: str
    ocr_text: str
    entities: dict[str, str]
    tags: tuple[str, ...]
    mood: tuple[str, ...]
    description: str


class SegmentationProvider(Protocol):
    """SAM 3.1."""

    def auto_masks(self, image: Image.Image) -> list[Mask]: ...

    def point_mask(self, image: Image.Image, points: Sequence[PointPrompt]) -> Mask: ...


class VisionLLMProvider(Protocol):
    """Muse Spark."""

    def enrich(self, scrap: Image.Image) -> Enrichment: ...
