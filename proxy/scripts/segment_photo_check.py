"""Day 2 check: run real auto-detect on desk photos and compare Plan A vs Plan B.

    .venv/Scripts/python scripts/segment_photo_check.py photo1.jpg photo2.jpg --plan both

For each photo and plan it saves <out>/<photo>_<plan>.png (tinted, numbered masks with
labels) and prints item count, labels, time and estimated cost. Uses real API credits:
Plan A ~ $0.003 per photo (1 Muse Spark call + 1 SAM request), Plan B ~ $0.02 per photo
(8 SAM concept requests).
"""

import argparse
import logging
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.config import Settings  # noqa: E402
from app.imaging import apply_cut_style, load_upload, mask_bbox  # noqa: E402
from app.providers import build_providers  # noqa: E402
from app.providers.real import CONCEPT_PROMPTS  # noqa: E402

SAM_PRICE_PER_REQUEST = 0.0025
TINTS = [(224, 122, 95), (61, 141, 174), (129, 178, 154), (242, 204, 143), (155, 107, 176), (209, 73, 91)]
PLANS = {"a": "spark_boxes", "b": "concepts"}


def overlay(photo: Image.Image, masks: list) -> Image.Image:
    canvas = photo.convert("RGBA")
    draw_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    for index, mask in enumerate(masks):
        tint = TINTS[index % len(TINTS)]
        alpha = (np.clip(mask.alpha, 0, 1) * 110).astype(np.uint8)
        layer = Image.new("RGBA", canvas.size, tint + (0,))
        layer.putalpha(Image.fromarray(alpha, "L"))
        draw_layer = Image.alpha_composite(draw_layer, layer)
    out = Image.alpha_composite(canvas, draw_layer)
    draw = ImageDraw.Draw(out)
    for index, mask in enumerate(masks):
        bbox = mask_bbox(mask.alpha)
        if bbox:
            draw.text((bbox[0] + 4, bbox[1] + 4), f"{index + 1} {mask.label or ''}", fill=(0, 0, 0, 255))
    return out.convert("RGB")


def run_plan(photo_path: Path, photo: Image.Image, plan: str, out_dir: Path) -> float:
    settings = Settings(use_real_providers=True, auto_detect_strategy=PLANS[plan])
    providers = build_providers(settings)
    started = time.perf_counter()
    masks = providers.segmentation.auto_masks(photo)
    seconds = time.perf_counter() - started

    overlay(photo, masks).save(out_dir / f"{photo_path.stem}_plan{plan.upper()}.png")
    for index, mask in enumerate(masks[:3]):  # a few real cutouts to inspect edges
        apply_cut_style(photo, mask.alpha, "tight", "m").save(out_dir / f"{photo_path.stem}_plan{plan.upper()}_cut{index + 1}.png")

    cost = SAM_PRICE_PER_REQUEST * (1 if plan == "a" else len(CONCEPT_PROMPTS))
    labels = ", ".join(m.label or "?" for m in masks)
    print(f"  Plan {plan.upper()}: {len(masks)} items in {seconds:.1f}s, ~${cost:.4f} SAM (+ Spark tokens for A) -> {labels}")
    return cost


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("photos", nargs="+", type=Path)
    parser.add_argument("--plan", choices=["a", "b", "both"], default="both")
    parser.add_argument("--out", type=Path, default=Path("segment_check_out"))
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="    %(message)s")

    if not Settings().meta_api_key:
        print("FAIL: MODEL_API_KEY is not set in proxy/.env.")
        return 1
    args.out.mkdir(parents=True, exist_ok=True)
    plans = ["a", "b"] if args.plan == "both" else [args.plan]
    total = 0.0
    for photo_path in args.photos:
        photo = load_upload(photo_path.read_bytes(), max_bytes=20 * 1024 * 1024, max_side=1536)
        print(f"{photo_path.name} ({photo.width}x{photo.height})")
        for plan in plans:
            total += run_plan(photo_path, photo, plan, args.out)
    print(f"\nEstimated SAM spend: ~${total:.3f}. Overlays and cutouts saved in {args.out.resolve()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
