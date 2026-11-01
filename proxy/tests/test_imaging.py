import numpy as np
from PIL import Image

from app.image_store import ImageStore
from app.imaging import (
    ROUGH_SOLIDITY,
    apply_cut_style,
    cut_from_original,
    dominant_palette,
    drop_islands,
    fill_holes,
    mask_bbox,
    mask_solidity,
)
from app.providers.mock import ellipse_mask

PHOTO = Image.new("RGB", (300, 200), (40, 90, 160))
ALPHA = ellipse_mask(300, 200, cx=150, cy=100, rx=60, ry=40)


def test_mask_bbox_of_empty_mask_is_none() -> None:
    assert mask_bbox(np.zeros((10, 10), dtype=np.float32)) is None


def test_mask_bbox_matches_ellipse() -> None:
    x, y, w, h = mask_bbox(ALPHA)
    assert abs(x - 90) <= 2 and abs(w - 120) <= 3
    assert abs(y - 60) <= 2 and abs(h - 80) <= 3


def test_margin_and_sticker_cuts_are_larger_than_tight() -> None:
    tight = apply_cut_style(PHOTO, ALPHA, "tight", "m")
    margin = apply_cut_style(PHOTO, ALPHA, "margin", "m")
    sticker = apply_cut_style(PHOTO, ALPHA, "sticker", "l")
    assert margin.width > tight.width and margin.height > tight.height
    assert sticker.width > margin.width


def test_bigger_cut_size_gives_bigger_margin() -> None:
    small = apply_cut_style(PHOTO, ALPHA, "margin", "s")
    large = apply_cut_style(PHOTO, ALPHA, "margin", "l")
    assert large.width > small.width


def _first_opaque_pixel_in_middle_row(image: Image.Image) -> np.ndarray:
    pixels = np.asarray(image)
    row = pixels[pixels.shape[0] // 2]
    return row[np.flatnonzero(row[:, 3] > 250)[0]]


def test_sticker_border_is_white_around_the_object() -> None:
    sticker = apply_cut_style(PHOTO, ALPHA, "sticker", "l")
    assert _first_opaque_pixel_in_middle_row(sticker)[:3].min() > 240
    center = np.asarray(sticker)[sticker.height // 2, sticker.width // 2]
    assert tuple(center) == (40, 90, 160, 255)


def test_margin_border_keeps_the_photo_background() -> None:
    margin = apply_cut_style(PHOTO, ALPHA, "margin", "l")
    assert tuple(_first_opaque_pixel_in_middle_row(margin)[:3]) == (40, 90, 160)


def test_fill_holes_closes_gaps_inside_a_mask() -> None:
    ring = ALPHA.copy()
    ring[90:110, 140:160] = 0.0  # a "glare" hole in the middle

    filled = fill_holes(ring)

    assert filled[100, 150] == 1.0
    assert filled[0, 0] == 0.0  # outside stays outside


def test_drop_islands_removes_specks_but_keeps_big_parts() -> None:
    alpha = np.zeros((100, 200), dtype=np.float32)
    alpha[20:80, 10:60] = 1.0  # main shape
    alpha[20:70, 80:120] = 1.0  # second letter, similar size: kept
    alpha[5:8, 180:184] = 1.0  # stray speck: dropped

    cleaned = drop_islands(alpha)

    assert cleaned[50, 30] == 1.0 and cleaned[40, 100] == 1.0
    assert cleaned[6, 182] == 0.0


def test_sticker_cut_has_no_white_blob_where_the_mask_had_a_hole() -> None:
    holey = ALPHA.copy()
    holey[90:110, 140:160] = 0.0

    sticker = np.asarray(apply_cut_style(PHOTO, holey, "sticker", "m"))

    center = sticker[sticker.shape[0] // 2, sticker.shape[1] // 2]
    assert tuple(center) == (40, 90, 160, 255)  # photo color, not white


def test_cut_from_original_scales_the_mask_up_to_full_resolution() -> None:
    original = Image.new("RGB", (900, 600), (40, 90, 160))  # 3x the 300x200 working photo

    scrap = cut_from_original(original, (300, 200), ALPHA, "tight", "m")
    small = apply_cut_style(PHOTO, ALPHA, "tight", "m")

    # Fixed padding/feather pixels don't scale, so compare ratios loosely.
    assert 2.7 <= scrap.width / small.width <= 3.1
    assert 2.7 <= scrap.height / small.height <= 3.1


def test_cut_from_original_keeps_border_width_relative_to_the_full_photo() -> None:
    original = Image.new("RGB", (900, 600), (40, 90, 160))
    _, _, outline_width, _ = mask_bbox(ALPHA)  # solid (>0.5) outline on the working photo

    margin = cut_from_original(original, (300, 200), ALPHA, "margin", "l")

    border = 0.02 * 900  # "l" is 2% of the full photo's long side, measured from the solid outline
    grown_per_side = (margin.width - outline_width * 3) / 2
    assert border <= grown_per_side <= border + 6  # + feather and crop padding


def test_dominant_palette_orders_by_frequency() -> None:
    image = Image.new("RGBA", (10, 10), (255, 0, 0, 255))
    image.paste((0, 0, 255, 255), (0, 0, 10, 3))
    assert dominant_palette(image, colors=2) == ["#FF0000", "#0000FF"]


def test_image_store_expires_entries() -> None:
    now = [0.0]
    store = ImageStore(ttl_seconds=10, clock=lambda: now[0])
    image_id = store.put(PHOTO)
    assert store.get(image_id).image is PHOTO
    now[0] = 11.0
    try:
        store.get(image_id)
    except Exception as exc:  # ApiError
        assert getattr(exc, "code", None) == "image_not_found"
    else:
        raise AssertionError("expected expiry")


def test_image_store_masks_are_read_only() -> None:
    store = ImageStore(ttl_seconds=60)
    image_id = store.put(PHOTO)
    (mask_id,) = store.add_masks(image_id, [ALPHA])
    masks = store.get(image_id).masks
    assert mask_id in masks
    try:
        masks["new"] = ALPHA  # type: ignore[index]
    except TypeError:
        pass
    else:
        raise AssertionError("masks mapping should be immutable")


def test_solidity_is_high_for_a_whole_piece_and_low_for_fragments() -> None:
    whole = np.zeros((200, 200), dtype=np.float32)
    whole[40:160, 30:170] = 1.0
    fragments = np.zeros((200, 200), dtype=np.float32)
    fragments[10:30, 10:190] = 1.0  # a long strip along the top...
    fragments[10:190, 170:190] = 1.0  # ...and down the side: an L of torn edges

    assert mask_solidity(whole) > 0.95
    assert mask_solidity(fragments) < ROUGH_SOLIDITY


def test_solidity_of_an_empty_mask_is_zero() -> None:
    assert mask_solidity(np.zeros((50, 50), dtype=np.float32)) == 0.0


def test_auto_enhance_softens_a_colour_cast_and_stretches_contrast() -> None:
    from app.imaging import auto_enhance

    rng = np.random.default_rng(0)
    grey = rng.uniform(90, 150, (60, 80, 1))
    dull_blue = np.concatenate([grey * 0.9, grey * 0.95, grey * 1.1], axis=2).clip(0, 255).astype(np.uint8)

    fixed = np.asarray(auto_enhance(Image.fromarray(dull_blue, "RGB")), dtype=np.float32)

    before_means = dull_blue.reshape(-1, 3).mean(axis=0)
    after_means = fixed.reshape(-1, 3).mean(axis=0)
    assert np.ptp(after_means) < np.ptp(before_means)  # channels closer together
    assert np.ptp(fixed) > np.ptp(dull_blue.astype(np.float32))  # wider tonal range


def test_auto_enhance_never_overcorrects_a_strongly_coloured_photo() -> None:
    from app.imaging import MAX_CAST_CORRECTION, auto_enhance

    brown_desk = Image.new("RGB", (40, 40), (160, 110, 70))

    r, g, b = auto_enhance(brown_desk).getpixel((0, 0))

    assert r > g > b  # still brown, not pushed to grey
    assert b <= 70 * (1 + MAX_CAST_CORRECTION) + 1
