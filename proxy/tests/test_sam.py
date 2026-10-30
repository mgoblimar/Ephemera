import numpy as np
import pytest
from PIL import Image

from app.imaging import mask_bbox
from app.providers.base import PointPrompt
from app.providers.sam import PixelBox, SamClient, _fast_records, _library_records, parse_sam_output
from tests.sam_fakes import full_raster, sam_line, sam_record

SIZE = (400, 300)
PHOTO = Image.new("RGB", SIZE, (200, 180, 150))


def test_mask_is_scaled_into_its_box_on_a_full_size_canvas() -> None:
    output = sam_line(sam_record(0, (10, 20, 110, 80), SIZE, full_raster()))

    masks = parse_sam_output(output, SIZE)

    alpha = masks["0"].alpha
    assert alpha.shape == (300, 400)
    assert mask_bbox(alpha) == (10, 20, 100, 60)


def test_low_resolution_raster_keeps_its_shape_when_upscaled() -> None:
    # Left half on, right half off, at 2x4 resolution, scaled into a 200x100 box.
    raster = np.array([[1, 1, 0, 0], [1, 1, 0, 0]], dtype=np.uint8)
    masks = parse_sam_output(sam_line(sam_record(0, (0, 0, 200, 100), SIZE, raster)), SIZE)

    x, _, w, h = mask_bbox(masks["0"].alpha)

    assert x == 0 and abs(w - 100) <= 25 and h == 100


def test_fast_parser_agrees_with_meta_parser() -> None:
    raster = np.array([[0, 1, 1, 0], [1, 1, 1, 1], [0, 1, 1, 0]], dtype=np.uint8)
    output = sam_line(
        sam_record(0, (10, 20, 110, 80), SIZE, raster),
        sam_record(3, (200, 100, 260, 190), SIZE, full_raster()),
    )

    fast = [(r.object_id, r.bounds, r.mask) for r in _fast_records(output)]
    library = [(r.object_id, r.bounds, r.mask) for r in _library_records(output)]

    assert fast == library and len(fast) == 2


def test_confidence_is_read_from_the_mask_record() -> None:
    record = sam_record(0, (10, 20, 110, 80), SIZE, full_raster()).replace("|><|mask;", ";c=0.42|><|mask;c=0.87;")

    masks = parse_sam_output(sam_line(record), SIZE)

    assert masks["0"].score == pytest.approx(0.87)


def test_corrupt_mask_is_skipped_not_fatal() -> None:
    good = sam_record(1, (200, 100, 260, 190), SIZE, full_raster())
    bad = "0<|box;x1=1;y1=1;x2=9;y2=9;w=400;h=300|><|mask;x=0;y=0;data=4,4,!@@@|>"

    masks = parse_sam_output(sam_line(bad, good), SIZE)

    assert list(masks) == ["1"]


def test_empty_response_means_no_masks() -> None:
    assert parse_sam_output("", SIZE) == {}


def test_segment_boxes_returns_masks_in_box_order_with_none_for_misses() -> None:
    def transport(prompt: str, image: Image.Image) -> str:
        assert "w=400;h=300" in prompt  # the declared size must match the photo sent
        return sam_line(sam_record(1, (200, 100, 300, 200), SIZE, full_raster()))  # object 0 not found

    masks = SamClient(transport).segment_boxes(PHOTO, [PixelBox(0, 0, 50, 50), PixelBox(200, 100, 300, 200)])

    assert masks[0] is None
    assert mask_bbox(masks[1].alpha) == (200, 100, 100, 100)


def test_segment_boxes_rejects_more_than_sixteen() -> None:
    with pytest.raises(ValueError):
        SamClient(lambda p, i: "").segment_boxes(PHOTO, [PixelBox(0, 0, 10, 10)] * 17)


def test_segment_points_sends_positive_and_negative_points() -> None:
    sent: list[str] = []

    def transport(prompt: str, image: Image.Image) -> str:
        sent.append(prompt)
        return sam_line(sam_record(0, (150, 100, 250, 200), SIZE, full_raster()))

    mask = SamClient(transport).segment_points(PHOTO, [PointPrompt(200, 150), PointPrompt(10, 10, positive=False)])

    assert "<|point;x=200;y=150;w=400;h=300|>" in sent[0]
    assert "-<|point;x=10;y=10;w=400;h=300|>" in sent[0]
    assert mask is not None and mask_bbox(mask.alpha) == (150, 100, 100, 100)


def test_concept_prompt_is_sent_as_plain_text() -> None:
    sent: list[str] = []

    def transport(prompt: str, image: Image.Image) -> str:
        sent.append(prompt)
        return sam_line(
            sam_record(0, (0, 0, 50, 50), SIZE, full_raster()),
            sam_record(1, (100, 100, 150, 150), SIZE, full_raster()),
        )

    masks = SamClient(transport).segment_concept(PHOTO, "ticket")

    assert sent == ["ticket"] and len(masks) == 2
