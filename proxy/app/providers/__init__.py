from dataclasses import dataclass

from app.config import Settings
from app.providers.base import SegmentationProvider, VisionLLMProvider
from app.providers.mock import MockSegmentationProvider, MockVisionLLMProvider


@dataclass(frozen=True)
class Providers:
    segmentation: SegmentationProvider
    vision: VisionLLMProvider
    mode: str


def build_providers(settings: Settings) -> Providers:
    if settings.use_real_providers:
        # Real SAM 3.1 / Muse adapters land on Day 2-4 once the hackathon API shapes are confirmed.
        raise RuntimeError("Real providers are not implemented yet. Set USE_REAL_PROVIDERS=false.")
    return Providers(segmentation=MockSegmentationProvider(), vision=MockVisionLLMProvider(), mode="mock")
