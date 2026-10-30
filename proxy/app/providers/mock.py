"""Deterministic offline providers. They cost nothing and need no network, so
the app can be built and demoed against them."""

from collections.abc import Sequence

import numpy as np
from PIL import Image

from app.providers.base import DetectedItem, Enrichment, Mask, PixelBox, PointPrompt

# (center x, center y, radius x, radius y) as fractions of the photo size.
MOCK_AUTO_ELLIPSES = (
    (0.28, 0.30, 0.17, 0.13),
    (0.72, 0.34, 0.15, 0.17),
    (0.50, 0.72, 0.22, 0.12),
)
MOCK_LABELS = ("ticket", "wrapper", "sticker")
MOCK_POINT_RADIUS_FRACTION = 0.12
SOFT_EDGE_PX = 3.0


def ellipse_mask(width: int, height: int, cx: float, cy: float, rx: float, ry: float) -> np.ndarray:
    """Ellipse mask in pixel units with a soft edge, mimicking soft model output."""
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    distance = np.sqrt(((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2)
    edge = SOFT_EDGE_PX / max(min(rx, ry), 1.0)
    return np.clip((1.0 - distance) / edge + 0.5, 0.0, 1.0).astype(np.float32)


class MockSegmentationProvider:
    def auto_masks(self, image: Image.Image) -> list[Mask]:
        width, height = image.size
        return [
            Mask(alpha=ellipse_mask(width, height, cx * width, cy * height, rx * width, ry * height), score=0.9)
            for cx, cy, rx, ry in MOCK_AUTO_ELLIPSES
        ]

    def detect_items(self, image: Image.Image) -> list[DetectedItem]:
        width, height = image.size
        return [
            DetectedItem(
                label=label,
                box=PixelBox(
                    left=round((cx - rx) * width),
                    top=round((cy - ry) * height),
                    right=round((cx + rx) * width),
                    bottom=round((cy + ry) * height),
                ),
            )
            for (cx, cy, rx, ry), label in zip(MOCK_AUTO_ELLIPSES, MOCK_LABELS, strict=True)
        ]

    def segment_boxes(self, image: Image.Image, boxes: Sequence[PixelBox]) -> list[Mask | None]:
        """An ellipse inscribed in each box."""
        width, height = image.size
        return [
            Mask(
                alpha=ellipse_mask(
                    width, height, (b.left + b.right) / 2, (b.top + b.bottom) / 2, (b.right - b.left) / 2, (b.bottom - b.top) / 2
                ),
                score=0.9,
            )
            for b in boxes
        ]

    def point_mask(self, image: Image.Image, points: Sequence[PointPrompt]) -> Mask:
        width, height = image.size
        positives = [p for p in points if p.positive] or list(points)
        cx = float(np.mean([p.x for p in positives]))
        cy = float(np.mean([p.y for p in positives]))
        radius = MOCK_POINT_RADIUS_FRACTION * min(width, height)
        return Mask(alpha=ellipse_mask(width, height, cx, cy, radius, radius), score=0.8)


class MockVisionLLMProvider:
    def enrich(self, scrap: Image.Image) -> Enrichment:
        return Enrichment(
            type="receipt",
            ocr_text="Café Lumière · 2x flat white · 14/03/2026 09:42",
            entities={"date": "2026-03-14", "place": "Café Lumière", "time": "09:42"},
            tags=("coffee", "morning", "cafe"),
            mood=("cozy", "quiet"),
            description="Faded thermal café receipt with a coffee ring (mock enrichment)",
        )
