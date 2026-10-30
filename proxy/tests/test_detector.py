from app.providers.detector import parse_detections
from app.providers.sam import PixelBox

SIZE = (400, 300)


def test_scales_0_to_1000_boxes_to_pixels() -> None:
    reply = '{"items": [{"label": "ticket", "box": [100, 200, 500, 600]}]}'

    (item,) = parse_detections(reply, SIZE)

    assert item.label == "ticket"
    assert item.box == PixelBox(left=40, top=60, right=200, bottom=180)


def test_accepts_json_inside_a_code_fence() -> None:
    reply = 'Here you go:\n```json\n{"items": [{"label": "tape", "box": [0, 0, 500, 500]}]}\n```'
    assert [i.label for i in parse_detections(reply, SIZE)] == ["tape"]


def test_unknown_label_becomes_other_and_swapped_corners_are_fixed() -> None:
    (item,) = parse_detections('{"items": [{"label": "spaceship", "box": [600, 600, 100, 100]}]}', SIZE)
    assert item.label == "other"
    assert item.box == PixelBox(left=40, top=30, right=240, bottom=180)


def test_drops_malformed_and_tiny_boxes_and_clamps_out_of_range() -> None:
    reply = """{"items": [
        {"label": "ticket", "box": [1, 2, 3]},
        {"label": "ticket", "box": "nope"},
        {"label": "note", "box": [500, 500, 502, 502]},
        {"label": "paper", "box": [-50, -50, 1200, 1200]}
    ]}"""

    items = parse_detections(reply, SIZE)

    assert [i.label for i in items] == ["paper"]
    assert items[0].box == PixelBox(left=0, top=0, right=400, bottom=300)


def test_non_json_reply_gives_no_items() -> None:
    assert parse_detections("I can see a lovely desk!", SIZE) == []


def test_caps_at_sixteen_items() -> None:
    boxes = ",".join('{"label": "note", "box": [0, 0, 500, 500]}' for _ in range(20))
    assert len(parse_detections('{"items": [' + boxes + "]}", SIZE)) == 16
