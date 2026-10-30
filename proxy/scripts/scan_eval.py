"""Scan quality test run: detect, split and cut a fixed photo set through the real routes.

    .venv/Scripts/python scripts/scan_eval.py test_photos/eval --split sumo,mnm_box,lemon_flatlay --tag baseline

Runs the app in-process with real providers (settings and key come from .env; the key is
never printed). Every chosen photo is detected, the first whole piece of each --split photo
is split into elements, and every piece is cut in one batched /scan/cut call (tight style, so
the shape score reflects the mask). Writes <out>/<tag>/<photo>.jpg review boards and
summary.json, and prints a table to compare runs.

Cost: ~₱0.01 per photo and per split (contributor Spark) + ₱0.16 per 16 cut pieces (SAM).
Contributor mode: Meta may train on these photos.
"""

import argparse
import base64
import io
import json
import sys
import time
from pathlib import Path

import numpy as np
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.config import Settings  # noqa: E402
from app.imaging import mask_solidity  # noqa: E402
from app.main import create_app  # noqa: E402

PESOS_PER_USD = 64
SPARK_CALL_PESOS = 0.01
SAM_REQUEST_PESOS = 0.0025 * PESOS_PER_USD
BOARD_PHOTO_SIDE = 900
TILE = 200
COLUMNS = 4


def main() -> None:
    args = _parse_args()
    out = Path(args.out) / args.tag
    out.mkdir(parents=True, exist_ok=True)
    settings = Settings(use_real_providers=not args.mock)
    print(f"vision={settings.vision_model} sam={settings.sam_model}")
    client = TestClient(create_app(settings))
    photos = sorted(p for p in Path(args.photos).iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png"})
    if args.only:
        photos = [p for p in photos if p.stem in args.only.split(",")]
    split_names = {n for n in args.split.split(",") if n}

    scans, refs, spark_calls, started = {}, [], 0, time.perf_counter()
    for path in photos:
        t = time.perf_counter()
        data = _post(client, "/scan/detect", files={"image": (path.name, path.read_bytes(), "image/jpeg")})
        spark_calls += 1
        pieces = [dict(p, element=False) for p in data["pieces"]]
        if path.stem in split_names and pieces:
            split = _post(client, "/scan/split", json={"image_id": data["image_id"], "piece_id": pieces[0]["id"]})
            spark_calls += 1
            pieces += [dict(p, element=True) for p in split["pieces"]]
        scans[path.stem] = {"path": path, "data": data, "pieces": pieces, "seconds": time.perf_counter() - t}
        refs += [{"image_id": data["image_id"], "piece_id": p["id"]} for p in pieces]

    cut = _post(client, "/scan/cut", json={"pieces": refs, "cut_style": "tight"}) if refs else None
    scraps = {(s["image_id"], s["piece_id"]): s for s in (cut or {}).get("scraps", [])}
    reasons = {(m["image_id"], m["piece_id"]): m.get("reason", "not_found") for m in (cut or {}).get("missed", [])}

    summary = []
    for name, scan in scans.items():
        row = _score(name, scan, scraps, reasons)
        _board(scan, scraps, reasons).save(out / f"{name}.jpg", quality=82)
        summary.append(row)
    cost = spark_calls * SPARK_CALL_PESOS + (cut or {}).get("sam_requests", 0) * SAM_REQUEST_PESOS
    (out / "summary.json").write_text(json.dumps({"photos": summary, "pesos": round(cost, 2)}, indent=2), encoding="utf-8")
    _print_table(summary, cost, time.perf_counter() - started, out)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("photos", help="folder of test photos")
    parser.add_argument("--split", default="", help="comma-separated photo names whose first piece is split")
    parser.add_argument("--tag", default="run", help="name of this run's output folder")
    parser.add_argument("--out", default="segment_check_out/eval")
    parser.add_argument("--only", default="", help="comma-separated photo names to run (default: all)")
    parser.add_argument("--mock", action="store_true", help="free dry run with the mock providers")
    return parser.parse_args()


def _post(client: TestClient, path: str, **kwargs: object) -> dict:
    response = client.post(path, **kwargs)
    body = response.json()
    if response.status_code != 200 or not body.get("ok"):
        raise SystemExit(f"{path} failed: {response.status_code} {body.get('error')}")
    return body["data"]


def _png(scrap: dict) -> Image.Image:
    return Image.open(io.BytesIO(base64.b64decode(scrap["png_base64"]))).convert("RGBA")


def _score(name: str, scan: dict, scraps: dict, reasons: dict) -> dict:
    image_id = scan["data"]["image_id"]
    rows = []
    for p in scan["pieces"]:
        key = (image_id, p["id"])
        if key in scraps:
            alpha = np.asarray(_png(scraps[key]))[:, :, 3].astype(np.float32) / 255
            rows.append({"label": p["label"], "element": p["element"], "result": "saved", "solidity": round(mask_solidity(alpha), 2)})
        else:
            rows.append({"label": p["label"], "element": p["element"], "result": reasons.get(key, "not_cut")})
    saved = [r["solidity"] for r in rows if r["result"] == "saved"]
    return {
        "photo": name,
        "pieces": sum(not r["element"] for r in rows),
        "elements": sum(r["element"] for r in rows),
        "saved": len(saved),
        "rough": sum(r["result"] == "rough" for r in rows),
        "not_found": sum(r["result"] == "not_found" for r in rows),
        "mean_solidity": round(float(np.mean(saved)), 2) if saved else None,
        "detect_seconds": round(scan["seconds"], 1),
        "items": rows,
    }


def _board(scan: dict, scraps: dict, reasons: dict) -> Image.Image:
    """Photo with numbered boxes (red = whole piece, blue = element) beside every cutout."""
    data, image_id = scan["data"], scan["data"]["image_id"]
    photo = ImageOps.exif_transpose(Image.open(scan["path"])).convert("RGB")
    photo = photo.resize((data["width"], data["height"]))
    draw = ImageDraw.Draw(photo)
    for i, p in enumerate(scan["pieces"], 1):
        x, y, w, h = p["box"]
        draw.rectangle((x, y, x + w, y + h), outline=(40, 90, 220) if p["element"] else (220, 50, 40), width=3)
        draw.text((x + 4, y + 4), f"{i} {p['label']}", fill=(255, 255, 0))
    photo.thumbnail((BOARD_PHOTO_SIDE, BOARD_PHOTO_SIDE))

    rows = max(1, -(-len(scan["pieces"]) // COLUMNS))
    board = Image.new("RGB", (photo.width + COLUMNS * TILE + 10, max(photo.height, rows * (TILE + 18))), "white")
    board.paste(photo, (0, 0))
    draw = ImageDraw.Draw(board)
    for i, p in enumerate(scan["pieces"]):
        x, y = photo.width + 10 + (i % COLUMNS) * TILE, (i // COLUMNS) * (TILE + 18)
        key = (image_id, p["id"])
        tile = Image.new("RGB", (TILE - 8, TILE - 8), (210, 210, 210))
        caption = f"{i + 1} {p['label']}"
        if key in scraps:
            cut = _png(scraps[key])
            cut.thumbnail((TILE - 12, TILE - 12))
            tile.paste(cut, ((tile.width - cut.width) // 2, (tile.height - cut.height) // 2), cut)
            caption += f" s{mask_solidity(np.asarray(cut)[:, :, 3] / 255):.2f}"
        else:
            caption += f" [{reasons.get(key, 'not cut')}]"
        board.paste(tile, (x, y))
        draw.text((x, y + TILE - 6), caption, fill=(0, 0, 0))
    return board


def _print_table(summary: list[dict], cost: float, seconds: float, out: Path) -> None:
    print(f"{'photo':16} {'pieces':>6} {'elems':>5} {'saved':>5} {'rough':>5} {'miss':>4} {'solid':>5} {'detect s':>8}")
    for r in summary:
        solid = "-" if r["mean_solidity"] is None else f"{r['mean_solidity']:.2f}"
        print(
            f"{r['photo']:16} {r['pieces']:>6} {r['elements']:>5} {r['saved']:>5} {r['rough']:>5}"
            f" {r['not_found']:>4} {solid:>5} {r['detect_seconds']:>8}"
        )
    print(f"cost ≈ ₱{cost:.2f}, {seconds:.0f}s total. Boards in {out}")


if __name__ == "__main__":
    main()
