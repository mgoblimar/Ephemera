import base64
import io

from fastapi.testclient import TestClient
from PIL import Image

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


def test_unknown_piece_is_a_404_envelope(client: TestClient) -> None:
    data = _detect(client)

    response = client.post("/scan/cut", json={"pieces": [{"image_id": data["image_id"], "piece_id": "nope"}]})

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "piece_not_found"
