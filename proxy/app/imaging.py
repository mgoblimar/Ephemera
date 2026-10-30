"""Image helpers: upload validation, mask previews, cut styles and palettes.

Masks are float32 arrays shaped (height, width) with values in [0, 1], so soft
(semi-transparent) edges from the segmentation model are preserved.
"""

import io
from typing import Literal

import numpy as np
from PIL import Image, ImageFilter, ImageOps, UnidentifiedImageError
from scipy.ndimage import binary_fill_holes, label
from scipy.spatial import ConvexHull, QhullError

from app.envelope import ApiError

CutStyle = Literal["tight", "sticker", "margin"]
CutSize = Literal["s", "m", "l"]

ALLOWED_FORMATS = frozenset({"JPEG", "PNG", "WEBP"})
# Border width for sticker/margin cuts, as a fraction of the photo's longer side.
CUT_SIZE_FRACTION: dict[str, float] = {"s": 0.006, "m": 0.012, "l": 0.02}
MASK_THRESHOLD = 0.5
FEATHER_RADIUS = 1.0
CROP_PADDING = 2
# For a Gaussian blur with sigma = r / 2, a straight edge's blurred value drops
# to about this level at distance r, so thresholding here dilates by ~r pixels.
DILATE_THRESHOLD = 0.023
STICKER_WHITE = 255
# Mask parts smaller than this fraction of the largest part are treated as stray specks.
ISLAND_KEEP_FRACTION = 0.15
# A cleaned mask filling less than this share of its convex hull is fragments, not a piece:
# on 76 real cutouts every one below 0.6 was junk, while curvy pieces (a bow) scored 0.72+.
ROUGH_SOLIDITY = 0.6
SOLIDITY_STRIDE = 4  # sample every 4th pixel; plenty for a shape measure


def load_upload(data: bytes, max_bytes: int, max_side: int, keep_alpha: bool = False) -> Image.Image:
    """Validate an uploaded image and return it upright and downscaled (RGB, or RGBA if keep_alpha)."""
    if not data:
        raise ApiError(400, "empty_upload", "The uploaded file is empty.")
    if len(data) > max_bytes:
        raise ApiError(413, "upload_too_large", f"Photos must be {max_bytes // (1024 * 1024)} MB or smaller.")
    try:
        image = Image.open(io.BytesIO(data))
        image_format = image.format
        image.load()
    except (UnidentifiedImageError, OSError) as exc:
        raise ApiError(415, "unsupported_image", "That file isn't a readable image.") from exc
    if image_format not in ALLOWED_FORMATS:
        raise ApiError(415, "unsupported_image", "Use a JPEG, PNG or WebP photo.")

    upright = ImageOps.exif_transpose(image).convert("RGBA" if keep_alpha else "RGB")
    upright.thumbnail((max_side, max_side))
    return upright


def mask_bbox(alpha: np.ndarray, threshold: float = MASK_THRESHOLD) -> tuple[int, int, int, int] | None:
    """Bounding box (x, y, width, height) of pixels above threshold, or None if empty."""
    rows = np.flatnonzero((alpha > threshold).any(axis=1))
    cols = np.flatnonzero((alpha > threshold).any(axis=0))
    if rows.size == 0:
        return None
    x0, x1 = int(cols[0]), int(cols[-1]) + 1
    y0, y1 = int(rows[0]), int(rows[-1]) + 1
    return x0, y0, x1 - x0, y1 - y0


def mask_area_fraction(alpha: np.ndarray) -> float:
    return float((alpha > MASK_THRESHOLD).mean())


def mask_preview_png(alpha: np.ndarray) -> bytes:
    """White RGBA PNG of the mask cropped to its bbox, for tinting in the app."""
    bbox = mask_bbox(alpha)
    if bbox is None:
        raise ApiError(422, "empty_mask", "The mask is empty.")
    x, y, w, h = bbox
    crop = alpha[y : y + h, x : x + w]
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (crop * 255).astype(np.uint8)
    return png_bytes(Image.fromarray(rgba, "RGBA"))


def dilate(alpha: np.ndarray, radius: float) -> np.ndarray:
    """Grow the mask outward by roughly `radius` pixels (fast blur-and-threshold)."""
    binary = Image.fromarray(((alpha > MASK_THRESHOLD) * 255).astype(np.uint8), "L")
    blurred = np.asarray(binary.filter(ImageFilter.GaussianBlur(radius / 2)), dtype=np.float32) / 255
    return (blurred > DILATE_THRESHOLD).astype(np.float32)


def feather(alpha: np.ndarray, radius: float = FEATHER_RADIUS) -> np.ndarray:
    image = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8), "L")
    return np.asarray(image.filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32) / 255


def drop_islands(alpha: np.ndarray, keep_fraction: float = ISLAND_KEEP_FRACTION) -> np.ndarray:
    """Remove small disconnected blobs (stray bits of neighbouring print) from a mask.

    Keeps every connected part at least `keep_fraction` of the largest part's size,
    so a cut-out word with separate letters survives but specks don't.
    """
    labels, count = label(alpha > MASK_THRESHOLD)
    if count <= 1:
        return alpha
    sizes = np.bincount(labels.ravel())[1:]
    keep = np.flatnonzero(sizes >= sizes.max() * keep_fraction) + 1
    return np.where(np.isin(labels, keep), alpha, 0.0).astype(np.float32)


def fill_holes(alpha: np.ndarray) -> np.ndarray:
    """Fill enclosed gaps (e.g. glare the model left out) - real scraps rarely have holes."""
    filled = binary_fill_holes(alpha > MASK_THRESHOLD)
    return np.maximum(alpha, filled.astype(np.float32))


def clean_mask(alpha: np.ndarray) -> np.ndarray:
    """Drop stray specks, then fill enclosed gaps: the mask a cutout is made from."""
    return fill_holes(drop_islands(alpha))


def mask_solidity(alpha: np.ndarray) -> float:
    """Share of its convex hull the mask fills: near 1 for a ticket, low for torn fragments."""
    small = alpha[::SOLIDITY_STRIDE, ::SOLIDITY_STRIDE] > MASK_THRESHOLD
    ys, xs = np.nonzero(small)
    if xs.size == 0:
        return 0.0
    try:
        hull = ConvexHull(np.column_stack([xs, ys])).volume  # in 2-D, "volume" is the area
    except QhullError:
        return 1.0  # a single row or column of pixels: a thin strip, not fragments
    # Hulls through pixel centres are slightly smaller than the pixels they wrap.
    return min(1.0, float(small.sum()) / max(hull, 1.0))


def border_px(size: CutSize, photo_size: tuple[int, int]) -> float:
    return CUT_SIZE_FRACTION[size] * max(photo_size)


def cut_from_original(
    original: Image.Image,
    working_size: tuple[int, int],
    alpha: np.ndarray,
    style: CutStyle,
    size: CutSize,
) -> Image.Image:
    """Apply a mask found on the small working photo to the full-resolution original.

    Only the region around the mask is scaled up and processed, so a big photo stays fast.
    """
    bbox = mask_bbox(alpha, threshold=0.01)
    if bbox is None:
        raise ApiError(422, "empty_mask", "The mask is empty.")
    scale = original.width / working_size[0]
    border = border_px(size, original.size)
    pad = border * 2 + FEATHER_RADIUS * 4 + CROP_PADDING  # room for the dilated border and feather
    x, y, w, h = bbox
    left = max(0, int(x * scale - pad))
    top = max(0, int(y * scale - pad))
    right = min(original.width, int((x + w) * scale + pad) + 1)
    bottom = min(original.height, int((y + h) * scale + pad) + 1)

    mask_image = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8), "L")
    region_mask = mask_image.resize(
        (right - left, bottom - top),
        Image.Resampling.BILINEAR,
        box=(left / scale, top / scale, right / scale, bottom / scale),
    )
    region_alpha = np.asarray(region_mask, dtype=np.float32) / 255
    return apply_cut_style(original.crop((left, top, right, bottom)), region_alpha, style, size, border=border)


def apply_cut_style(
    image: Image.Image,
    alpha: np.ndarray,
    style: CutStyle,
    size: CutSize,
    border: float | None = None,
) -> Image.Image:
    """Cut a scrap out of the photo as a cropped RGBA image in the requested style.

    `border` overrides the sticker/margin width in pixels (needed when `image` is a crop).
    """
    rgb = np.asarray(image.convert("RGB"), dtype=np.float32)
    border = border_px(size, image.size) if border is None else border
    alpha = clean_mask(alpha)

    if style == "tight":
        out_rgb, out_alpha = rgb, feather(alpha)
    elif style == "margin":
        out_rgb, out_alpha = rgb, feather(np.maximum(alpha, dilate(alpha, border)))
    else:  # sticker: composite the object over a solid white outline
        weight = alpha[..., None]
        out_rgb = rgb * weight + STICKER_WHITE * (1 - weight)
        out_alpha = feather(np.maximum(alpha, dilate(alpha, border)))

    rgba = np.dstack([out_rgb, out_alpha * 255]).clip(0, 255).astype(np.uint8)
    bbox = mask_bbox(out_alpha, threshold=0.01)
    if bbox is None:
        raise ApiError(422, "empty_mask", "The mask is empty.")
    x, y, w, h = bbox
    pad = CROP_PADDING
    height, width = out_alpha.shape
    crop = rgba[max(0, y - pad) : min(height, y + h + pad), max(0, x - pad) : min(width, x + w + pad)]
    return Image.fromarray(crop, "RGBA")


def dominant_palette(image: Image.Image, colors: int = 4, sample: int = 5000, iterations: int = 10) -> list[str]:
    """Dominant colors of the opaque pixels as hex strings, most common first (k-means)."""
    rgba = np.asarray(image.convert("RGBA"))
    pixels = rgba[rgba[..., 3] > 128][:, :3].astype(np.float32)
    if pixels.shape[0] == 0:
        return []
    rng = np.random.default_rng(0)
    if pixels.shape[0] > sample:
        pixels = pixels[rng.choice(pixels.shape[0], sample, replace=False)]
    distinct = np.unique(pixels, axis=0)
    k = min(colors, distinct.shape[0])
    centers = distinct[rng.choice(distinct.shape[0], k, replace=False)]
    for _ in range(iterations):
        labels = np.argmin(((pixels[:, None, :] - centers[None, :, :]) ** 2).sum(axis=2), axis=1)
        centers = np.array(
            [pixels[labels == i].mean(axis=0) if np.any(labels == i) else centers[i] for i in range(k)]
        )
    counts = np.bincount(labels, minlength=k)
    order = np.argsort(-counts)
    ordered = centers[order][counts[order] > 0]
    hexes = ["#{:02X}{:02X}{:02X}".format(*(int(round(c)) for c in center)) for center in ordered]
    return list(dict.fromkeys(hexes))  # clusters can round to the same hex; keep the first


def jpeg_bytes(image: Image.Image, quality: int = 88) -> bytes:
    buffer = io.BytesIO()
    image.convert("RGB").save(buffer, format="JPEG", quality=quality)
    return buffer.getvalue()


def png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()
