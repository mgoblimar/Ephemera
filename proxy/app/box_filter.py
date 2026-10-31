"""Server-side clean-up of Spark's boxes before they're offered as pieces.

Spark sometimes lists a sticker sheet as well as each sticker on it, the same piece twice, or (in
Split) an element whose box swallows its neighbours or the whole scrap. Those cut out as junk.
"""

from app.providers.base import DetectedItem, PixelBox

DUPLICATE_IOU = 0.6  # two boxes this alike are the same piece; the first (largest / most eye-catching) is kept
INSIDE_FRACTION = 0.8  # a box holding this much of another box contains it
MIN_CONTAINED = 2  # a box containing this many other boxes is a sheet or a merge, not a piece
WHOLE_SCRAP_FRACTION = 0.85  # a Split element this big is just the whole scrap again


def clean_boxes(items: list[DetectedItem]) -> list[DetectedItem]:
    """Drop boxes that contain several other boxes, then near-duplicates, keeping the model's order."""
    singles = [item for i, item in enumerate(items) if _contained_count(i, items) < MIN_CONTAINED]
    kept: list[DetectedItem] = []
    for item in singles:
        if all(iou(item.box, other.box) < DUPLICATE_IOU for other in kept):
            kept.append(item)
    return kept


def not_whole_scrap(box: PixelBox, parent: PixelBox) -> bool:
    return _area(box) < WHOLE_SCRAP_FRACTION * _area(parent)


def iou(a: PixelBox, b: PixelBox) -> float:
    overlap = _overlap(a, b)
    union = _area(a) + _area(b) - overlap
    return overlap / union if union > 0 else 0.0


def _contained_count(index: int, items: list[DetectedItem]) -> int:
    """How many other boxes sit (mostly) inside items[index]; exact copies are left to the duplicate check."""
    box = items[index].box
    return sum(
        1
        for j, other in enumerate(items)
        if j != index
        and other.box != box
        and _area(other.box) > 0
        and _overlap(box, other.box) >= INSIDE_FRACTION * _area(other.box)
    )


def _overlap(a: PixelBox, b: PixelBox) -> int:
    width = min(a.right, b.right) - max(a.left, b.left)
    height = min(a.bottom, b.bottom) - max(a.top, b.top)
    return max(0, width) * max(0, height)


def _area(box: PixelBox) -> int:
    return max(0, box.right - box.left) * max(0, box.bottom - box.top)
