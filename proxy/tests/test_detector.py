from PIL import Image

from app.providers.detector import Y_BIAS_FRACTION, SparkItemDetector, parse_detections
from app.providers.sam import PixelBox

SIZE = (400, 300)
BIAS = round(Y_BIAS_FRACTION * 400)  # Spark's boxes sit this low; parsing moves them back up


def test_boxes_are_read_as_pixels_and_moved_up_by_sparks_bias() -> None:
    reply = '{"items": [{"label": "ticket", "box": [40, 60, 200.4, 180]}]}'

    (item,) = parse_detections(reply, SIZE)

    assert item.label == "ticket"
    assert item.box == PixelBox(left=40, top=60 - BIAS, right=200, bottom=180 - BIAS)


def test_prompts_state_the_image_size_in_pixels() -> None:
    prompts: list[str] = []
    detector = SparkItemDetector(lambda system, text, image: prompts.append(text) or '{"items": []}')

    detector.detect(Image.new("RGB", (1536, 1024)))
    detector.detect_elements(Image.new("RGB", (640, 480)))

    assert "1536x1024 pixels" in prompts[0] and "(1536,1024)" in prompts[0]
    assert "640x480 pixel" in prompts[1]


def test_accepts_json_inside_a_code_fence() -> None:
    reply = 'Here you go:\n```json\n{"items": [{"label": "tape", "box": [0, 0, 500, 500]}]}\n```'
    assert [i.label for i in parse_detections(reply, SIZE)] == ["tape"]


def test_unknown_label_becomes_other_and_swapped_corners_are_fixed() -> None:
    (item,) = parse_detections('{"items": [{"label": "spaceship", "box": [240, 180, 40, 30]}]}', SIZE)
    assert item.label == "other"
    assert item.box == PixelBox(left=40, top=30 - BIAS, right=240, bottom=180 - BIAS)


def test_drops_malformed_and_tiny_boxes_and_clamps_out_of_range() -> None:
    reply = """{"items": [
        {"label": "ticket", "box": [1, 2, 3]},
        {"label": "ticket", "box": "nope"},
        {"label": "note", "box": [200, 150, 201, 151]},
        {"label": "paper", "box": [-50, -50, 1200, 1200]}
    ]}"""

    items = parse_detections(reply, SIZE)

    assert [i.label for i in items] == ["paper"]
    assert items[0].box == PixelBox(left=0, top=0, right=400, bottom=300)


def test_non_json_reply_gives_no_items() -> None:
    assert parse_detections("I can see a lovely desk!", SIZE) == []


def test_caps_at_sixteen_items() -> None:
    boxes = ",".join('{"label": "note", "box": [0, 0, 200, 150]}' for _ in range(20))
    assert len(parse_detections('{"items": [' + boxes + "]}", SIZE)) == 16
