import json

from PIL import Image

from app.imaging import mask_bbox
from app.providers import build_providers
from app.providers.base import PointPrompt
from app.providers.detector import SparkItemDetector
from app.providers.real import CONCEPT_PROMPTS, RealSegmentationProvider
from app.providers.sam import SamClient
from tests.conftest import make_settings
from tests.sam_fakes import full_raster, prompt_object_ids, sam_line, sam_record

SIZE = (400, 300)
PHOTO = Image.new("RGB", SIZE, (200, 180, 150))


def _detector(items: list[dict]) -> SparkItemDetector:
    return SparkItemDetector(lambda system, text, image: json.dumps({"items": items}))


def test_plan_a_sends_detected_boxes_to_sam_and_keeps_labels() -> None:
    sam_calls: list[str] = []

    def sam(prompt: str, image: Image.Image) -> str:
        sam_calls.append(prompt)
        records = [sam_record(i, (i * 200, 0, i * 200 + 100, 100), SIZE, full_raster()) for i in prompt_object_ids(prompt)]
        return sam_line(*records)

    detector = _detector(
        [{"label": "ticket", "box": [0, 0, 100, 100]}, {"label": "botanical", "box": [200, 0, 300, 100]}]
    )
    provider = RealSegmentationProvider(SamClient(sam), detector, strategy="spark_boxes")

    masks = provider.auto_masks(PHOTO)

    assert len(sam_calls) == 1  # all boxes in one SAM request
    assert [m.label for m in masks] == ["ticket", "botanical"]


def test_plan_a_with_nothing_detected_makes_no_sam_call() -> None:
    def sam(prompt: str, image: Image.Image) -> str:
        raise AssertionError("SAM should not be called")

    provider = RealSegmentationProvider(SamClient(sam), _detector([]), strategy="spark_boxes")

    assert provider.auto_masks(PHOTO) == []


def test_plan_b_runs_every_concept_and_dedupes_overlaps() -> None:
    def sam(prompt: str, image: Image.Image) -> str:
        if prompt in ("ticket", "receipt"):  # both find the same item
            return sam_line(sam_record(0, (10, 10, 110, 110), SIZE, full_raster()))
        if prompt == "flower":
            return sam_line(sam_record(0, (250, 150, 350, 250), SIZE, full_raster()))
        return ""

    provider = RealSegmentationProvider(SamClient(sam), _detector([]), strategy="concepts")

    masks = provider.auto_masks(PHOTO)

    assert len(masks) == 2
    assert {m.label for m in masks} <= {label for _, label in CONCEPT_PROMPTS}
    assert "botanical" in {m.label for m in masks}


def test_point_with_no_match_returns_empty_mask() -> None:
    provider = RealSegmentationProvider(SamClient(lambda p, i: ""), _detector([]), strategy="spark_boxes")

    mask = provider.point_mask(PHOTO, [PointPrompt(5, 5)])

    assert mask_bbox(mask.alpha) is None


def test_build_providers_real_mode_needs_no_network_to_construct() -> None:
    providers = build_providers(make_settings(use_real_providers=True, meta_api_key="test-key"))
    assert providers.mode == "real"
    assert isinstance(providers.segmentation, RealSegmentationProvider)
