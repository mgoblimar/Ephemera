"""Image helpers: upload validation, mask previews, cut styles and palettes.

Masks are float32 arrays shaped (height, width) with values in [0, 1], so soft
(semi-transparent) edges from the segmentation model are preserved.
"""

import io
from typing import Literal

import numpy as np
from PIL import Image, ImageFilter, ImageOps, UnidentifiedImageError

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


def apply_cut_style(image: Image.Image, alpha: np.ndarray, style: CutStyle, size: CutSize) -> Image.Image:
    """Cut a scrap out of the photo as a cropped RGBA image in the requested style."""
    rgb = np.asarray(image.convert("RGB"), dtype=np.float32)
    border = CUT_SIZE_FRACTION[size] * max(image.size)

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
