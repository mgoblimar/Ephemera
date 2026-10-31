from app.box_filter import clean_boxes, iou, not_whole_scrap
from app.providers.base import DetectedItem, PixelBox


def _item(left: int, top: int, right: int, bottom: int, label: str = "sticker") -> DetectedItem:
    return DetectedItem(label=label, box=PixelBox(left, top, right, bottom))


def test_separate_pieces_are_all_kept_in_order() -> None:
    items = [_item(0, 0, 100, 100), _item(200, 0, 300, 100), _item(0, 200, 100, 300)]

    assert clean_boxes(items) == items


def test_a_sheet_listed_with_its_stickers_is_dropped() -> None:
    sheet = _item(0, 0, 500, 300, label="paper")
    stickers = [_item(20, 20, 120, 120), _item(200, 20, 300, 120), _item(20, 150, 120, 250)]

    assert clean_boxes([sheet, *stickers]) == stickers


def test_a_box_around_just_one_other_is_kept() -> None:
    wrapper = _item(0, 0, 400, 400, label="wrapper")
    sticker_on_it = _item(50, 50, 150, 150)

    assert clean_boxes([wrapper, sticker_on_it]) == [wrapper, sticker_on_it]


def test_near_duplicates_keep_the_first() -> None:
    first = _item(0, 0, 100, 100)
    again = _item(5, 5, 105, 102)

    assert clean_boxes([first, again]) == [first]


def test_exact_copies_collapse_to_one() -> None:
    piece = _item(0, 0, 100, 100)

    assert clean_boxes([piece, piece, piece]) == [piece]


def test_overlapping_neighbours_are_both_kept() -> None:
    a, b = _item(0, 0, 100, 100), _item(70, 0, 170, 100)

    assert iou(a.box, b.box) < 0.6
    assert clean_boxes([a, b]) == [a, b]


def test_an_element_as_big_as_its_scrap_is_the_whole_scrap() -> None:
    parent = PixelBox(0, 0, 1000, 600)

    assert not not_whole_scrap(PixelBox(10, 10, 990, 590), parent)
    assert not_whole_scrap(PixelBox(100, 100, 600, 500), parent)
