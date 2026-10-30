from dataclasses import dataclass

from app.config import Settings
from app.providers.base import SegmentationProvider, VisionLLMProvider
from app.providers.detector import SparkItemDetector
from app.providers.enricher import SparkEnricher
from app.providers.meta_client import build_client
from app.providers.mock import MockSegmentationProvider, MockVisionLLMProvider
from app.providers.real import RealSegmentationProvider, sam_transport, vision_transport
from app.providers.sam import SamClient


@dataclass(frozen=True)
class Providers:
    segmentation: SegmentationProvider
    vision: VisionLLMProvider
    mode: str


def build_providers(settings: Settings) -> Providers:
    if not settings.use_real_providers:
        return Providers(segmentation=MockSegmentationProvider(), vision=MockVisionLLMProvider(), mode="mock")

    client = build_client(settings)
    segmentation = RealSegmentationProvider(
        sam=SamClient(sam_transport(client, settings)),
        detector=SparkItemDetector(vision_transport(client, settings)),
        strategy=settings.auto_detect_strategy,
    )
    vision = SparkEnricher(vision_transport(client, settings, what="Enrichment"))
    return Providers(segmentation=segmentation, vision=vision, mode="real")
