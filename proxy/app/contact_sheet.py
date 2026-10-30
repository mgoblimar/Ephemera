"""Pack chosen pieces from many photos onto one contact sheet, so SAM cuts them
all in a single request (SAM bills per request and takes up to 16 objects).

Each piece is cropped from its full-size photo with some padding, scaled into its
own cell, and its box is sent as a box prompt. Masks come back in sheet
coordinates and are mapped back onto each piece's crop of the original photo.
"""

import math
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np
from PIL import Image

from app.imaging import CUT_SIZE_FRACTION
from app.providers.base import PixelBox
from app.providers.sam import MAX_OBJECTS_PER_REQUEST

CELL_SIZE = 512  # each piece gets at most this many pixels on its long side
GUTTER = 24  # neutral gap between cells so SAM never merges neighbours
GUTTER_COLOR = (128, 128, 128)
CONTEXT_FRACTION = 0.08  # extra photo around each box, so SAM sees the item's edges


@dataclass(frozen=True)
class Piece:
    photo: Image.Image  # full-resolution original
    box: PixelBox  # piece's box in that photo's pixels


@dataclass(frozen=True)
class SheetCell:
    region: PixelBox  # area of the original photo copied into the cell
    cell: PixelBox  # where that area sits on the sheet
    prompt_box: PixelBox  # the piece's own box, in sheet pixels


@dataclass(frozen=True)
class ContactSheet:
    image: Image.Image
    cells: tuple[SheetCell, ...]


def build_sheet(pieces: Sequence[Piece]) -> ContactSheet:
    if not 0 < len(pieces) <= MAX_OBJECTS_PER_REQUEST:
        raise ValueError(f"A contact sheet holds 1-{MAX_OBJECTS_PER_REQUEST} pieces.")
    columns = math.ceil(math.sqrt(len(pieces)))
    rows = math.ceil(len(pieces) / columns)
    sheet = Image.new("RGB", (columns * (CELL_SIZE + GUTTER) + GUTTER, rows * (CELL_SIZE + GUTTER) + GUTTER), GUTTER_COLOR)

    cells = []
    for index, piece in enumerate(pieces):
        region = _padded_region(piece)
        crop = piece.photo.convert("RGB").crop((region.left, region.top, region.right, region.bottom))
        scale = min(1.0, CELL_SIZE / max(crop.size))  # never upscale: it adds no detail
        crop = crop.resize((max(1, round(crop.width * scale)), max(1, round(crop.height * scale))), Image.Resampling.LANCZOS)
        x = GUTTER + (index % columns) * (CELL_SIZE + GUTTER)
        y = GUTTER + (index // columns) * (CELL_SIZE + GUTTER)
        sheet.paste(crop, (x, y))

        def to_sheet(px: float, py: float, x: int = x, y: int = y, s: float = scale) -> tuple[int, int]:
            return x + round((px - region.left) * s), y + round((py - region.top) * s)

        (bl, bt), (br, bb) = to_sheet(piece.box.left, piece.box.top), to_sheet(piece.box.right, piece.box.bottom)
        cells.append(
            SheetCell(
                region=region,
                cell=PixelBox(x, y, x + crop.width, y + crop.height),
                prompt_box=PixelBox(bl, bt, max(br, bl + 1), max(bb, bt + 1)),
            )
        )
    return ContactSheet(image=sheet, cells=tuple(cells))


def mask_for_piece(sheet_alpha: np.ndarray, cell: SheetCell) -> np.ndarray:
    """Cut the piece's mask out of the sheet and scale it to the original photo region."""
    c = cell.cell
    cell_alpha = np.clip(sheet_alpha[c.top : c.bottom, c.left : c.right], 0, 1)
    image = Image.fromarray((cell_alpha * 255).astype(np.uint8), "L")
    r = cell.region
    full = image.resize((r.right - r.left, r.bottom - r.top), Image.Resampling.BILINEAR)
    return np.asarray(full, dtype=np.float32) / 255


def _padded_region(piece: Piece) -> PixelBox:
    """Box plus surrounding context, with room for the widest sticker/margin border."""
    b, (width, height) = piece.box, piece.photo.size
    border_room = 2.5 * max(CUT_SIZE_FRACTION.values()) * max(width, height)
    pad = max(CONTEXT_FRACTION * max(b.right - b.left, b.bottom - b.top), border_room)
    return PixelBox(
        left=max(0, int(b.left - pad)),
        top=max(0, int(b.top - pad)),
        right=min(width, int(math.ceil(b.right + pad))),
        bottom=min(height, int(math.ceil(b.bottom + pad))),
    )
