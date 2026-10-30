import json

from fastapi.testclient import TestClient

from app.agent.layout import (
    MAX_OVERLAP,
    MAX_TILT_DEG,
    PAGE_ASPECT,
    LayoutDesigner,
    LayoutScrap,
    Placement,
    finalize_layout,
    overlap_fraction,
    parse_layout,
)

SCRAPS = [
    LayoutScrap(id="a", aspect=0.75, type="sticker"),
    LayoutScrap(id="b", aspect=1.4, type="ticket"),
    LayoutScrap(id="c", aspect=0.5, type="wrapper"),
]
ASPECTS = {s.id: s.aspect for s in SCRAPS}


def _inside_page(p: Placement, aspect: float) -> bool:
    half_w, half_h = p.width / 2, p.width * aspect / PAGE_ASPECT / 2
    eps = 1e-9
    return p.cx - half_w >= -eps and p.cx + half_w <= 1 + eps and p.cy - half_h >= -eps and p.cy + half_h <= 1 + eps


def test_uses_the_models_placements_and_captions() -> None:
    reply = json.dumps(
        {
            "placements": [
                {"id": "a", "cx": 0.3, "cy": 0.25, "width": 0.5, "rotation_deg": -6, "z": 2},
                {"id": "b", "cx": 0.75, "cy": 0.45, "width": 0.3, "rotation_deg": 8, "z": 1},
                {"id": "c", "cx": 0.4, "cy": 0.7, "width": 0.4, "rotation_deg": 3, "z": 0},
            ],
            "captions": [{"text": "ignored", "cx": 0.6, "cy": 0.92, "size": 0.05, "rotation_deg": -3}],
        }
    )

    layout = LayoutDesigner(lambda system, user: reply).layout("Title", "hero top left", "kraft", SCRAPS, ["hello"])

    a = layout.placements[0]
    assert (a.id, round(a.cx, 2), round(a.width, 2)) == ("a", 0.3, 0.5)
    assert [p.z for p in layout.placements] == [2, 1, 0]
    caption = layout.captions[0]
    assert caption.text == "hello" and caption.cy == 0.92  # our caption text, the model's placement


def test_prompt_lists_each_scrap_with_its_shape() -> None:
    sent: list[str] = []

    def transport(system: str, user: str) -> str:
        sent.append(user)
        return "{}"

    LayoutDesigner(transport).layout("Cafe", "", "cream", SCRAPS, [])

    assert '"id": "b"' in sent[0] and '"aspect_h_over_w": 1.4' in sent[0]


def test_forgotten_or_unknown_scraps_are_handled() -> None:
    reply = json.dumps({"placements": [{"id": "ghost", "cx": 0.5}, {"id": "a", "cx": 0.2, "cy": 0.2, "width": 0.3}]})

    layout = parse_layout(reply, SCRAPS, [])

    assert [p.id for p in layout.placements] == ["a", "b", "c"]  # every scrap placed, ghost dropped


def test_garbage_reply_still_gives_a_usable_layout() -> None:
    layout = finalize_layout(parse_layout("not json", SCRAPS, ["cap"]), SCRAPS)

    assert len(layout.placements) == 3 and layout.captions[0].text == "cap"
    assert all(_inside_page(p, ASPECTS[p.id]) for p in layout.placements)


def test_out_of_range_values_are_clamped_onto_the_page() -> None:
    reply = json.dumps(
        {"placements": [{"id": "a", "cx": 1.4, "cy": -0.3, "width": 3, "rotation_deg": 80, "z": 0}]}
    )

    layout = finalize_layout(parse_layout(reply, SCRAPS[:1], []), SCRAPS[:1])

    a = layout.placements[0]
    assert _inside_page(a, ASPECTS["a"])
    assert abs(a.rotation_deg) <= MAX_TILT_DEG


def test_heavy_overlaps_are_pushed_apart() -> None:
    stacked = json.dumps(
        {"placements": [{"id": s.id, "cx": 0.5, "cy": 0.5, "width": 0.35, "rotation_deg": 0, "z": i} for i, s in enumerate(SCRAPS)]}
    )

    layout = finalize_layout(parse_layout(stacked, SCRAPS, []), SCRAPS)

    placed = layout.placements
    for i, p in enumerate(placed):
        assert _inside_page(p, ASPECTS[p.id])
        for q in placed[i + 1 :]:
            assert overlap_fraction(p, q, ASPECTS[p.id], ASPECTS[q.id]) <= MAX_OVERLAP + 0.05


def test_layout_route_with_mock_designer(client: TestClient) -> None:
    body = {
        "title": "Slow Sunday",
        "paper": "kraft",
        "scraps": [{"id": s.id, "aspect": s.aspect, "type": s.type} for s in SCRAPS],
        "captions": ["9:42"],
    }

    data = client.post("/agent/layout", json=body).json()["data"]

    assert [p["id"] for p in data["placements"]] == ["a", "b", "c"]
    assert data["captions"][0]["text"] == "9:42"


def test_layout_route_rejects_no_scraps(client: TestClient) -> None:
    assert client.post("/agent/layout", json={"scraps": []}).status_code == 422
