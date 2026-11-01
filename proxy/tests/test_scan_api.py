import base64
import io
from collections.abc import Sequence
from dataclasses import replace

import numpy as np
from fastapi.testclient import TestClient
from PIL import Image

from app.providers.base import DetectedItem, Mask, PixelBox
from app.providers.mock import MockSegmentationProvider

from tests.conftest import photo_bytes


def _detect(client: TestClient, size: tuple[int, int] = (1200, 900)) -> dict:
    response = client.post("/scan/detect", files={"image": ("desk.png", photo_bytes(size, fmt="PNG"), "image/png")})
    assert response.status_code == 200
    return response.json()["data"]


def test_detect_returns_pieces_with_labels_boxes_and_thumbnails(client: TestClient) -> None:
    data = _detect(client)

    assert [p["label"] for p in data["pieces"]] == ["ticket", "wrapper", "sticker"]
    x, y, w, h = data["pieces"][0]["box"]
    assert w > 0 and h > 0 and x + w <= data["width"] and y + h <= data["height"]
    thumb = Image.open(io.BytesIO(base64.b64decode(data["pieces"][0]["thumb_jpeg"])))
    assert max(thumb.size) <= 256


def test_cut_combines_pieces_from_two_photos_into_one_sam_request(client: TestClient) -> None:
    first, second = _detect(client), _detect(client, (900, 1200))
    refs = [{"image_id": first["image_id"], "piece_id": p["id"]} for p in first["pieces"]]
    refs += [{"image_id": second["image_id"], "piece_id": second["pieces"][1]["id"]}]

    data = client.post("/scan/cut", json={"pieces": refs, "cut_style": "sticker"}).json()["data"]

    assert data["sam_requests"] == 1
    assert data["missed"] == []
    assert [s["label"] for s in data["scraps"]] == ["ticket", "wrapper", "sticker", "wrapper"]
    scrap = Image.open(io.BytesIO(base64.b64decode(data["scraps"][0]["png_base64"])))
    assert scrap.mode == "RGBA" and scrap.getpixel((0, 0))[3] == 0


def test_more_than_sixteen_pieces_are_cut_in_batches(client: TestClient) -> None:
    photos = [_detect(client) for _ in range(6)]  # 18 pieces
    refs = [{"image_id": d["image_id"], "piece_id": p["id"]} for d in photos for p in d["pieces"]]

    data = client.post("/scan/cut", json={"pieces": refs}).json()["data"]

    assert data["sam_requests"] == 2 and len(data["scraps"]) == 18


def test_cutouts_use_the_full_resolution_photo(client: TestClient) -> None:
    data = _detect(client, (3000, 2000))  # working copy is 1536 wide
    piece = data["pieces"][0]

    scrap = client.post(
        "/scan/cut", json={"pieces": [{"image_id": data["image_id"], "piece_id": piece["id"]}]}
    ).json()["data"]["scraps"][0]

    assert scrap["width"] > piece["box"][2] * 1.8


def test_a_piece_can_have_its_own_cut_style(client: TestClient) -> None:
    data = _detect(client)
    ref = {"image_id": data["image_id"], "piece_id": data["pieces"][0]["id"]}

    cut = client.post(
        "/scan/cut", json={"pieces": [ref, {**ref, "cut_style": "sticker"}], "cut_style": "tight"}
    ).json()["data"]["scraps"]

    tight, sticker = cut
    assert sticker["width"] > tight["width"]  # the sticker cut adds a white outline


def test_split_returns_elements_inside_the_parent_piece(client: TestClient) -> None:
    data = _detect(client, (3000, 2000))
    parent = data["pieces"][1]

    split = client.post("/scan/split", json={"image_id": data["image_id"], "piece_id": parent["id"]}).json()["data"]

    assert split["parent_id"] == parent["id"]
    assert [p["label"] for p in split["pieces"]] == ["logo", "lettering"]
    px, py, pw, ph = parent["box"]
    for element in split["pieces"]:
        x, y, w, h = element["box"]
        assert px <= x and py <= y and x + w <= px + pw + 1 and y + h <= py + ph + 1


def test_whole_piece_and_its_elements_cut_in_one_request(client: TestClient) -> None:
    data = _detect(client, (3000, 2000))
    parent = data["pieces"][0]
    split = client.post("/scan/split", json={"image_id": data["image_id"], "piece_id": parent["id"]}).json()["data"]
    refs = [{"image_id": data["image_id"], "piece_id": p["id"]} for p in [parent, *split["pieces"]]]

    cut = client.post("/scan/cut", json={"pieces": refs, "cut_style": "sticker"}).json()["data"]

    assert cut["sam_requests"] == 1
    assert [s["label"] for s in cut["scraps"]] == ["ticket", "logo", "lettering"]
    whole, logo = cut["scraps"][0], cut["scraps"][1]
    assert logo["width"] < whole["width"]


class _SliverElements(MockSegmentationProvider):
    """The mock's logo and lettering, plus a thin strip of side text and a speck of a badge."""

    def detect_elements(self, scrap: Image.Image) -> list[DetectedItem]:
        width, height = scrap.size
        return [
            *super().detect_elements(scrap),
            DetectedItem(label="lettering", box=PixelBox(width - 12, 0, width - 2, height)),
            DetectedItem(label="badge", box=PixelBox(0, 0, width // 12, height // 12)),
        ]


def test_split_drops_slivers_and_specks(client: TestClient) -> None:
    client.app.state.providers = replace(client.app.state.providers, segmentation=_SliverElements())
    data = _detect(client, (3000, 2000))

    split = client.post(
        "/scan/split", json={"image_id": data["image_id"], "piece_id": data["pieces"][1]["id"]}
    ).json()["data"]

    assert [p["label"] for p in split["pieces"]] == ["logo", "lettering"]


def test_split_unknown_piece_is_404(client: TestClient) -> None:
    data = _detect(client)

    response = client.post("/scan/split", json={"image_id": data["image_id"], "piece_id": "nope"})

    assert response.status_code == 404


def test_unknown_piece_is_a_404_envelope(client: TestClient) -> None:
    data = _detect(client)

    response = client.post("/scan/cut", json={"pieces": [{"image_id": data["image_id"], "piece_id": "nope"}]})

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "piece_not_found"


class _FragmentSam(MockSegmentationProvider):
    """Returns an L of thin strips for the second box: the shape of a torn, half-hidden piece."""

    def segment_boxes(self, image: Image.Image, boxes: Sequence[PixelBox]) -> list[Mask | None]:
        masks = super().segment_boxes(image, boxes)
        b = boxes[1]
        alpha = np.zeros((image.height, image.width), dtype=np.float32)
        alpha[b.top : b.top + 6, b.left : b.right] = 1.0
        alpha[b.top : b.bottom, b.right - 6 : b.right] = 1.0
        masks[1] = Mask(alpha=alpha, score=0.9)
        return masks


def test_broken_cutouts_are_reported_as_rough_instead_of_saved(client: TestClient) -> None:
    client.app.state.providers = replace(client.app.state.providers, segmentation=_FragmentSam())
    photo = _detect(client)
    refs = [{"image_id": photo["image_id"], "piece_id": p["id"]} for p in photo["pieces"]]

    data = client.post("/scan/cut", json={"pieces": refs, "cut_style": "tight"}).json()["data"]

    assert [s["piece_id"] for s in data["scraps"]] == [photo["pieces"][0]["id"], photo["pieces"][2]["id"]]
    assert data["missed"] == [{**refs[1], "reason": "rough"}]


def test_detect_can_skip_auto_enhance(client: TestClient) -> None:
    response = client.post(
        "/scan/detect",
        files={"image": ("desk.png", photo_bytes((1200, 900), fmt="PNG"), "image/png")},
        data={"enhance": "false"},
    )

    assert response.status_code == 200
    assert response.json()["data"]["pieces"]
