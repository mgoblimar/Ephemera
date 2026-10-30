"""Provider interfaces. Each Meta model sits behind one of these, so the mock
and real implementations are interchangeable."""

from collections.abc import Sequence
from dataclasses import dataclass
from typing import TYPE_CHECKING, Protocol

import numpy as np
from PIL import Image

if TYPE_CHECKING:
    from app.agent.archive_search import ScrapSummary
    from app.agent.layout import LayoutScrap, PageLayout
    from app.agent.planner import BlendPlan


@dataclass(frozen=True)
class PointPrompt:
    x: float
    y: float
    positive: bool = True


@dataclass(frozen=True)
class PixelBox:
    left: int
    top: int
    right: int  # exclusive
    bottom: int  # exclusive


@dataclass(frozen=True)
class DetectedItem:
    label: str
    box: PixelBox


@dataclass(frozen=True)
class Mask:
    alpha: np.ndarray  # (height, width) float32 in [0, 1]
    score: float
    label: str | None = None  # scrap type when known, e.g. "ticket"


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

    def detect_items(self, image: Image.Image) -> list[DetectedItem]:
        """Find pieces without cutting them (cheap: no SAM call)."""
        ...

    def segment_boxes(self, image: Image.Image, boxes: Sequence[PixelBox]) -> list[Mask | None]:
        """Cut up to 16 boxes in one SAM request."""
        ...

    def detect_elements(self, scrap: Image.Image) -> list[DetectedItem]:
        """Design elements (logos, lettering, illustrations...) inside one scrap's crop."""
        ...


class AgentPlanner(Protocol):
    """Theme Blend agent (Muse Wonder): theme + archive summaries -> Blend Plan."""

    def plan(self, theme: str, pinned_ids: Sequence[str], archive: Sequence["ScrapSummary"]) -> "BlendPlan": ...


class PageDesigner(Protocol):
    """Theme Blend build step: arranges an approved plan's scraps on a page."""

    def layout(
        self, title: str, layout_intent: str, paper: str, scraps: Sequence["LayoutScrap"], captions: Sequence[str]
    ) -> "PageLayout": ...


class ImageGenerator(Protocol):
    """Muse Image: a text prompt in, one picture out."""

    def generate(self, prompt: str) -> Image.Image: ...


class VisionLLMProvider(Protocol):
    """Muse Spark."""

    def enrich(self, scrap: Image.Image) -> Enrichment: ...
