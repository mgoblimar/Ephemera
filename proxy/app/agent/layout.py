"""Theme Blend agent, build step (SPEC 4.6): arrange an approved plan on a page.

The model proposes a composition (position, width, tilt, layer for each scrap,
plus caption placement). We then make it safe: clamp everything onto the page
and push apart scraps that cover too much of each other. Some overlap is part of
the junk-journal look; heavy overlap hides scraps.

Coordinates are page fractions: cx, cy in [0, 1] (0,0 top-left); `width` is a
fraction of page width; a scrap's height fraction is width * aspect / PAGE_ASPECT.
"""

import json
import logging
import math
from collections.abc import Callable, Sequence
from dataclasses import asdict, dataclass, replace

from app.providers.detector import extract_json

logger = logging.getLogger(__name__)

PAGE_ASPECT = 1.414  # height / width, A5 portrait (matches the app)
MIN_WIDTH, MAX_WIDTH = 0.14, 0.7
MAX_TILT_DEG = 15.0
MAX_OVERLAP = 0.35  # of the smaller scrap's area
RELAX_STEPS = 60
RELAX_PUSH = 0.02
CAPTION_MIN, CAPTION_MAX = 0.04, 0.09  # font size as a fraction of page width
MAX_CAPTIONS = 3

# (system prompt, user prompt) -> model text reply.
TextTransport = Callable[[str, str], str]

SYSTEM_PROMPT = "You are an expert junk-journal page designer. You reply with JSON only."


@dataclass(frozen=True)
class LayoutScrap:
    id: str
    aspect: float  # height / width of the scrap image
    type: str = "other"
    description: str = ""


@dataclass(frozen=True)
class Placement:
    id: str
    cx: float
    cy: float
    width: float
    rotation_deg: float
    z: int


@dataclass(frozen=True)
class CaptionPlacement:
    text: str
    cx: float
    cy: float
    size: float
    rotation_deg: float


@dataclass(frozen=True)
class PageLayout:
    placements: tuple[Placement, ...]
    captions: tuple[CaptionPlacement, ...]

    def to_json(self) -> dict[str, object]:
        return {
            "placements": [asdict(p) for p in self.placements],
            "captions": [asdict(c) for c in self.captions],
        }


def build_prompt(title: str, layout_intent: str, paper: str, scraps: Sequence[LayoutScrap], captions: Sequence[str]) -> str:
    items = [{"id": s.id, "type": s.type, "aspect_h_over_w": round(s.aspect, 2), "about": s.description[:80]} for s in scraps]
    return f"""Arrange these scraps on one A5 portrait journal page (height = {PAGE_ASPECT} x width).
Page title: {title}
Design idea: {layout_intent or "a balanced, layered collage"}
Paper: {paper}
Scraps: {json.dumps(items)}
Captions: {json.dumps(list(captions)[:MAX_CAPTIONS])}

Rules:
- Coordinates are fractions of the page: cx, cy in 0..1 from the top-left; "width" is a fraction of page width ({MIN_WIDTH}-{MAX_WIDTH}).
- Make a pleasing junk-journal composition: one hero scrap larger, others smaller, slight tilts (-12..12 degrees),
  light layering is good but never hide more than a third of any scrap. Keep scraps inside the page.
- Leave room for each caption (font size 0.04-0.08 of page width), usually near the bottom or beside the hero.
- "z": higher draws on top.
Reply with only:
{{"placements": [{{"id": "...", "cx": 0.5, "cy": 0.3, "width": 0.4, "rotation_deg": -5, "z": 1}}],
 "captions": [{{"text": "...", "cx": 0.5, "cy": 0.9, "size": 0.06, "rotation_deg": -2}}]}}"""


class LayoutDesigner:
    def __init__(self, transport: TextTransport) -> None:
        self._transport = transport

    def layout(
        self, title: str, layout_intent: str, paper: str, scraps: Sequence[LayoutScrap], captions: Sequence[str]
    ) -> PageLayout:
        reply = self._transport(SYSTEM_PROMPT, build_prompt(title, layout_intent, paper, scraps, captions))
        return finalize_layout(parse_layout(reply, scraps, captions), scraps)


def parse_layout(reply: str, scraps: Sequence[LayoutScrap], captions: Sequence[str]) -> PageLayout:
    """Read the model's layout; scraps it forgot get a fallback slot."""
    data = extract_json(reply)
    if not isinstance(data, dict):
        logger.warning("Layout reply was not JSON: %.200s", reply)
        data = {}
    known = {s.id for s in scraps}
    placements: dict[str, Placement] = {}
    for raw in data.get("placements", []) if isinstance(data.get("placements"), list) else []:
        if isinstance(raw, dict) and raw.get("id") in known and raw["id"] not in placements:
            placements[raw["id"]] = Placement(
                id=raw["id"],
                cx=_num(raw.get("cx"), 0.5),
                cy=_num(raw.get("cy"), 0.5),
                width=_num(raw.get("width"), 0.35),
                rotation_deg=_num(raw.get("rotation_deg"), 0.0),
                z=int(_num(raw.get("z"), len(placements))),
            )
    for index, scrap in enumerate(scraps):
        if scrap.id not in placements:
            placements[scrap.id] = _fallback_slot(scrap.id, index, len(placements))
    model_captions = [c for c in data.get("captions", []) if isinstance(c, dict)] if isinstance(data.get("captions"), list) else []
    placed_captions = []
    for i, text in enumerate(list(captions)[:MAX_CAPTIONS]):
        raw = model_captions[i] if i < len(model_captions) else {}
        placed_captions.append(
            CaptionPlacement(
                text=text,
                cx=_num(raw.get("cx"), 0.5),
                cy=_num(raw.get("cy"), 0.9 - i * 0.06),
                size=_num(raw.get("size"), 0.06),
                rotation_deg=_num(raw.get("rotation_deg"), -2.0),
            )
        )
    ordered = tuple(placements[s.id] for s in scraps)
    return PageLayout(placements=ordered, captions=tuple(placed_captions))


def finalize_layout(layout: PageLayout, scraps: Sequence[LayoutScrap]) -> PageLayout:
    """Clamp onto the page, push apart heavy overlaps, and normalise layers."""
    aspects = {s.id: max(0.1, min(s.aspect, 10.0)) for s in scraps}
    placed = [_clamp(p, aspects[p.id]) for p in layout.placements]
    placed = _relax(placed, aspects)
    by_layer = sorted(placed, key=lambda p: p.z)
    placed = [replace(p, z=next(i for i, q in enumerate(by_layer) if q.id == p.id)) for p in placed]
    captions = tuple(
        replace(
            c,
            cx=min(max(c.cx, 0.1), 0.9),
            cy=min(max(c.cy, 0.05), 0.97),
            size=min(max(c.size, CAPTION_MIN), CAPTION_MAX),
            rotation_deg=min(max(c.rotation_deg, -MAX_TILT_DEG), MAX_TILT_DEG),
        )
        for c in layout.captions
    )
    return PageLayout(placements=tuple(placed), captions=captions)


def overlap_fraction(a: Placement, b: Placement, aspect_a: float, aspect_b: float) -> float:
    """Overlap area as a fraction of the smaller box (rotation ignored: tilts are small)."""
    ax0, ay0, ax1, ay1 = _box(a, aspect_a)
    bx0, by0, bx1, by1 = _box(b, aspect_b)
    w = min(ax1, bx1) - max(ax0, bx0)
    h = min(ay1, by1) - max(ay0, by0)
    if w <= 0 or h <= 0:
        return 0.0
    smaller = min((ax1 - ax0) * (ay1 - ay0), (bx1 - bx0) * (by1 - by0))
    return (w * h) / smaller if smaller > 0 else 0.0


def _relax(placed: list[Placement], aspects: dict[str, float]) -> list[Placement]:
    for _ in range(RELAX_STEPS):
        moved = False
        for i in range(len(placed)):
            for j in range(i + 1, len(placed)):
                a, b = placed[i], placed[j]
                if overlap_fraction(a, b, aspects[a.id], aspects[b.id]) <= MAX_OVERLAP:
                    continue
                dx, dy = b.cx - a.cx, (b.cy - a.cy) * PAGE_ASPECT
                dist = math.hypot(dx, dy) or 1e-6
                if dist < 1e-3:  # same centre: separate diagonally
                    dx, dy, dist = 1.0, 1.0, math.sqrt(2)
                ux, uy = dx / dist * RELAX_PUSH, dy / dist * RELAX_PUSH / PAGE_ASPECT
                placed[i] = _clamp(replace(a, cx=a.cx - ux, cy=a.cy - uy), aspects[a.id])
                placed[j] = _clamp(replace(b, cx=b.cx + ux, cy=b.cy + uy), aspects[b.id])
                moved = True
        if not moved:
            break
    # Still too crowded (e.g. many big scraps): shrink everything a little and try once more.
    if any(
        overlap_fraction(p, q, aspects[p.id], aspects[q.id]) > MAX_OVERLAP
        for i, p in enumerate(placed)
        for q in placed[i + 1 :]
    ):
        placed = [_clamp(replace(p, width=max(MIN_WIDTH, p.width * 0.85)), aspects[p.id]) for p in placed]
    return placed


def _box(p: Placement, aspect: float) -> tuple[float, float, float, float]:
    half_w = p.width / 2
    half_h = p.width * aspect / PAGE_ASPECT / 2
    return p.cx - half_w, p.cy - half_h, p.cx + half_w, p.cy + half_h


def _clamp(p: Placement, aspect: float) -> Placement:
    width = min(max(p.width, MIN_WIDTH), MAX_WIDTH)
    height = width * aspect / PAGE_ASPECT
    if height > 0.9:  # very tall scraps: shrink to fit the page height
        width *= 0.9 / height
        height = 0.9
    cx = min(max(p.cx, width / 2), 1 - width / 2)
    cy = min(max(p.cy, height / 2), 1 - height / 2)
    tilt = min(max(p.rotation_deg, -MAX_TILT_DEG), MAX_TILT_DEG)
    return replace(p, cx=cx, cy=cy, width=width, rotation_deg=tilt)


def _fallback_slot(scrap_id: str, index: int, z: int) -> Placement:
    column, row = index % 2, index // 2
    return Placement(id=scrap_id, cx=0.3 + 0.4 * column, cy=0.2 + 0.22 * row, width=0.32, rotation_deg=(-6 if index % 2 else 6), z=z)


def _num(value: object, default: float) -> float:
    try:
        number = float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return default
    return number if math.isfinite(number) else default


class MockLayoutDesigner:
    """Free, offline: fallback grid slots, then the same safety pass."""

    def layout(
        self, title: str, layout_intent: str, paper: str, scraps: Sequence[LayoutScrap], captions: Sequence[str]
    ) -> PageLayout:
        return finalize_layout(parse_layout("{}", scraps, captions), scraps)
