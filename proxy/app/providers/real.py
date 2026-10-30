"""Real segmentation: SAM 3.1 for cutouts, Muse Spark for finding items (Plan A),
or several SAM concept prompts (Plan B). Selected with AUTO_DETECT_STRATEGY."""

import logging
from collections.abc import Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace

import numpy as np
from openai import OpenAI
from PIL import Image

from app.config import Settings
from app.providers.base import DetectedItem, Mask, PixelBox, PointPrompt
from app.providers.detector import SparkItemDetector, VisionTransport
from app.providers.meta_client import call_model, image_data_url, log_usage
from app.providers.sam import SamClient, SamTransport, mask_iou

logger = logging.getLogger(__name__)

# Plan B phrases, each paired with the scrap type it implies.
CONCEPT_PROMPTS: tuple[tuple[str, str], ...] = (
    ("ticket", "ticket"),
    ("receipt", "receipt"),
    ("wrapper", "wrapper"),
    ("flower", "botanical"),
    ("washi tape", "tape"),
    ("sticker", "sticker"),
    ("paper", "paper"),
    ("photo", "photo"),
)
DUPLICATE_IOU = 0.6  # concept results overlapping more than this are the same item
# Finding boxes needs little deliberation; extra reasoning tokens mostly add latency.
DETECTION_REASONING_EFFORT = "minimal"


class RealSegmentationProvider:
    def __init__(self, sam: SamClient, detector: SparkItemDetector, strategy: str) -> None:
        self._sam = sam
        self._detector = detector
        self._strategy = strategy

    def auto_masks(self, image: Image.Image) -> list[Mask]:
        if self._strategy == "concepts":
            return self._concept_masks(image)
        return self._detected_masks(image)

    def point_mask(self, image: Image.Image, points: Sequence[PointPrompt]) -> Mask:
        mask = self._sam.segment_points(image, points)
        if mask is None:
            # An all-zero mask makes the route answer "Nothing found at that spot".
            return Mask(alpha=_empty(image), score=0.0)
        return mask

    def detect_items(self, image: Image.Image) -> list[DetectedItem]:
        items = self._detector.detect(image)
        logger.info("Detector found %d items: %s", len(items), [i.label for i in items])
        return items

    def segment_boxes(self, image: Image.Image, boxes: Sequence[PixelBox]) -> list[Mask | None]:
        return self._sam.segment_boxes(image, boxes)

    def detect_elements(self, scrap: Image.Image) -> list[DetectedItem]:
        elements = self._detector.detect_elements(scrap)
        logger.info("Split found %d elements: %s", len(elements), [e.label for e in elements])
        return elements

    def _detected_masks(self, image: Image.Image) -> list[Mask]:
        items = self._detector.detect(image)
        logger.info("Detector found %d items: %s", len(items), [i.label for i in items])
        masks = self._sam.segment_boxes(image, [item.box for item in items])
        return [replace(mask, label=item.label) for item, mask in zip(items, masks, strict=True) if mask is not None]

    def _concept_masks(self, image: Image.Image) -> list[Mask]:
        with ThreadPoolExecutor(max_workers=len(CONCEPT_PROMPTS)) as pool:
            results = list(pool.map(lambda c: self._sam.segment_concept(image, c[0]), CONCEPT_PROMPTS))
        labelled = [
            replace(mask, label=label)
            for (_, label), masks in zip(CONCEPT_PROMPTS, results, strict=True)
            for mask in masks
        ]
        return _dedupe(labelled)


def _dedupe(masks: list[Mask]) -> list[Mask]:
    """Keep the highest-scoring mask among heavily overlapping ones."""
    kept: list[Mask] = []
    for mask in sorted(masks, key=lambda m: m.score, reverse=True):
        if all(mask_iou(mask.alpha, other.alpha) < DUPLICATE_IOU for other in kept):
            kept.append(mask)
    return kept


def _empty(image: Image.Image) -> np.ndarray:
    return np.zeros((image.height, image.width), dtype=np.float32)


def sam_transport(client: OpenAI, settings: Settings) -> SamTransport:
    def send(prompt: str, image: Image.Image) -> str:
        response = call_model(
            "SAM segmentation",
            lambda: client.responses.create(
                model=settings.sam_model,
                input=[
                    {
                        "type": "message",
                        "role": "user",
                        "content": [
                            {"type": "input_text", "text": prompt},
                            {"type": "input_image", "image_url": image_data_url(image)},
                        ],
                    }
                ],
                metadata={"include_confidence": "true"},
            ),
        )
        log_usage("SAM segmentation", settings.sam_model, getattr(response, "usage", None))
        return response.output_text or ""

    return send


def vision_transport(client: OpenAI, settings: Settings) -> VisionTransport:
    def send(system: str, text: str, image: Image.Image) -> str:
        response = call_model(
            "Item detection",
            lambda: client.chat.completions.create(
                model=settings.vision_model,
                messages=[
                    {"role": "system", "content": system},
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": text},
                            {"type": "image_url", "image_url": {"url": image_data_url(image)}},
                        ],
                    },
                ],
                reasoning_effort=DETECTION_REASONING_EFFORT,
            ),
        )
        log_usage("Item detection", settings.vision_model, response.usage)
        return response.choices[0].message.content or ""

    return send
