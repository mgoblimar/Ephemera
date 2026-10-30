"""Generated decorations (SPEC 4.6 `generate_ephemera`): prompt Muse Image for one
stamp / tape strip / label / ticket / sticker on a plain background, then lift it
off that background so it arrives as a cut-out like any scanned scrap.

The background is removed here rather than with SAM: the picture is asked for on
plain white, so "everything connected to the border that looks like the border"
is the background. Free, instant, and it keeps white parts inside the design.
"""

import numpy as np
from PIL import Image
from scipy.ndimage import binary_closing, binary_fill_holes, label

from app.envelope import ApiError
from app.imaging import CROP_PADDING, clean_mask, feather, mask_bbox

# How each kind should look, in plain words the image model follows well.
_KIND_LOOK = {
    "stamp": "a vintage postage stamp with a perforated edge",
    "tape": "a single strip of washi tape with torn ends, lying flat",
    "label": "a small paper label or gift tag, fully designed: a short printed word, a simple border and a tiny illustration",
    "ticket": "a small printed paper ticket stub, fully designed: a bold title, a little illustration, a serial number and fine print, with a perforated tear-off edge",
    "sticker": "a cute die-cut sticker with a thin white outline",
}

# A pixel this far (RGB distance) from the border colour counts as part of the design.
BACKGROUND_TOLERANCE = 38.0
BORDER_SAMPLE = 4  # px strip around the edge used to read the background colour
# Gaps narrower than ~2x this share of the image (perforation notches) get sealed.
GAP_FRACTION = 0.012


def ephemera_prompt(kind: str, prompt: str, palette: list[str]) -> str:
    colours = f" Colours: {', '.join(palette[:6])}." if palette else ""
    return (
        f"{_KIND_LOOK.get(kind, 'a small paper decoration')} for a junk journal: {prompt.strip()}.{colours} "
        "One single object, centred, seen straight from above, about three quarters of the frame wide, with a clear margin of plain background "
        "on every side so none of it touches the edge; its design fills the object with no large empty areas, "
        "isolated on a plain pure white background, no shadow, no hands, no extra objects, flat lighting."
    )


def _seal_gaps(design: np.ndarray) -> np.ndarray:
    """Close small gaps in the design's outline (perforations, dashed borders), so
    near-white paper inside it isn't mistaken for background leaking in."""
    radius = max(2, round(GAP_FRACTION * min(design.shape)))
    padded = np.pad(design, radius)
    closed = binary_closing(padded, iterations=radius)[radius:-radius, radius:-radius]
    return binary_fill_holes(closed | design)


def lift_off_background(image: Image.Image) -> Image.Image:
    """RGBA cut-out of the design: drops the plain background connected to the border."""
    rgb = np.asarray(image.convert("RGB"), dtype=np.float32)
    height, width, _ = rgb.shape
    b = BORDER_SAMPLE
    border = np.concatenate([rgb[:b].reshape(-1, 3), rgb[-b:].reshape(-1, 3), rgb[:, :b].reshape(-1, 3), rgb[:, -b:].reshape(-1, 3)])
    background_colour = np.median(border, axis=0)
    looks_like_background = np.linalg.norm(rgb - background_colour, axis=2) < BACKGROUND_TOLERANCE

    # Only background-coloured regions that reach the edge are background: white
    # inside a stamp or label (enclosed by its design) stays.
    regions, _ = label(looks_like_background)
    edge_regions = np.unique(np.concatenate([regions[0], regions[-1], regions[:, 0], regions[:, -1]]))
    background = np.isin(regions, edge_regions[edge_regions > 0])
    alpha = clean_mask(_seal_gaps(~background).astype(np.float32))

    bbox = mask_bbox(alpha)
    if bbox is None or bbox[2] * bbox[3] < 0.01 * width * height:
        raise ApiError(422, "empty_decoration", "The decoration came out blank. Try again.")
    x, y, w, h = bbox
    rgba = np.dstack([rgb, feather(alpha) * 255]).clip(0, 255).astype(np.uint8)
    pad = CROP_PADDING
    crop = rgba[max(0, y - pad) : min(height, y + h + pad), max(0, x - pad) : min(width, x + w + pad)]
    return Image.fromarray(crop, "RGBA")
