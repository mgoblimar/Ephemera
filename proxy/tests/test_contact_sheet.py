import numpy as np
import pytest
from PIL import Image

from app.contact_sheet import CELL_SIZE, GUTTER, Piece, build_sheet, mask_for_piece
from app.imaging import mask_bbox
from app.providers.base import PixelBox

PHOTO_A = Image.new("RGB", (3000, 2000), (200, 180, 150))
PHOTO_B = Image.new("RGB", (800, 600), (40, 90, 160))


def test_pieces_from_several_photos_share_one_sheet_without_overlap() -> None:
    pieces = [Piece(PHOTO_A, PixelBox(100, 100, 900, 700)), Piece(PHOTO_B, PixelBox(300, 200, 400, 300))] * 3

    sheet = build_sheet(pieces)

    assert len(sheet.cells) == 6
    boxes = [c.cell for c in sheet.cells]
    for i, a in enumerate(boxes):
        for b in boxes[i + 1 :]:
            assert a.right + GUTTER <= b.left or b.right + GUTTER <= a.left or a.bottom + GUTTER <= b.top or b.bottom + GUTTER <= a.top


def test_large_pieces_are_scaled_down_and_small_ones_not_up() -> None:
    sheet = build_sheet([Piece(PHOTO_A, PixelBox(100, 100, 2100, 1100)), Piece(PHOTO_B, PixelBox(300, 200, 360, 260))])

    big, small = sheet.cells
    assert max(big.cell.right - big.cell.left, big.cell.bottom - big.cell.top) == CELL_SIZE
    assert small.cell.right - small.cell.left == small.region.right - small.region.left  # kept at 1:1


def test_prompt_box_sits_inside_its_cell() -> None:
    sheet = build_sheet([Piece(PHOTO_A, PixelBox(1000, 500, 1600, 1500))])
    (cell,) = sheet.cells

    p, c = cell.prompt_box, cell.cell
    assert c.left <= p.left < p.right <= c.right and c.top <= p.top < p.bottom <= c.bottom


def test_sheet_mask_maps_back_onto_the_original_box() -> None:
    piece = Piece(PHOTO_A, PixelBox(1000, 500, 1600, 1500))
    sheet = build_sheet([piece])
    (cell,) = sheet.cells
    sheet_alpha = np.zeros((sheet.image.height, sheet.image.width), dtype=np.float32)
    p = cell.prompt_box
    sheet_alpha[p.top : p.bottom, p.left : p.right] = 1.0  # SAM "found" exactly the box

    region_alpha = mask_for_piece(sheet_alpha, cell)

    x, y, w, h = mask_bbox(region_alpha)
    r = cell.region
    assert abs(r.left + x - 1000) <= 4 and abs(r.top + y - 500) <= 4
    assert abs(w - 600) <= 6 and abs(h - 1000) <= 6


def test_rejects_empty_and_oversized_batches() -> None:
    with pytest.raises(ValueError):
        build_sheet([])
    with pytest.raises(ValueError):
        build_sheet([Piece(PHOTO_B, PixelBox(0, 0, 10, 10))] * 17)
