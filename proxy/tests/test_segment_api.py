import base64
import io

from fastapi.testclient import TestClient
from PIL import Image

from app.main import create_app
from tests.conftest import make_settings, photo_bytes


def test_health_reports_mock_providers(client: TestClient) -> None:
    body = client.get("/health").json()
    assert body == {"ok": True, "data": {"status": "ok", "providers": "mock"}, "error": None}


def test_auto_segment_returns_masks_with_previews(segmented: dict) -> None:
    assert segmented["width"] == 400 and segmented["height"] == 300
    assert len(segmented["masks"]) == 3
    mask = segmented["masks"][0]
    x, y, w, h = mask["bbox"]
    assert w > 0 and h > 0 and x + w <= 400 and y + h <= 300
    preview = Image.open(io.BytesIO(base64.b64decode(mask["preview_png"])))
    assert preview.mode == "RGBA" and preview.size == (w, h)
    photo = Image.open(io.BytesIO(base64.b64decode(segmented["photo_jpeg"])))
    assert photo.size == (400, 300)


def test_auto_segment_applies_exif_rotation(client: TestClient) -> None:
    buffer = io.BytesIO()
    exif = Image.Exif()
    exif[0x0112] = 6  # orientation: rotate 90° clockwise to display upright
    Image.new("RGB", (400, 300), (10, 20, 30)).save(buffer, format="JPEG", exif=exif)
    data = client.post("/segment/auto", files={"image": ("phone.jpg", buffer.getvalue(), "image/jpeg")}).json()["data"]
    assert (data["width"], data["height"]) == (300, 400)


def test_auto_segment_downscales_large_photos(client: TestClient) -> None:
    response = client.post("/segment/auto", files={"image": ("big.jpg", photo_bytes((3000, 2000)), "image/jpeg")})
    data = response.json()["data"]
    assert max(data["width"], data["height"]) == 1536


def test_cutouts_come_from_the_full_resolution_photo(client: TestClient) -> None:
    data = client.post("/segment/auto", files={"image": ("big.png", photo_bytes((3000, 2000), fmt="PNG"), "image/png")}).json()["data"]
    mask = data["masks"][0]

    scrap = client.post("/cutout", json={"image_id": data["image_id"], "mask_ids": [mask["id"]]}).json()["data"]["scraps"][0]

    working_width = mask["bbox"][2]  # mask bbox on the 1536px working photo
    assert scrap["width"] > working_width * 1.8  # cut from the 3072px original, ~2x sharper


def test_rejects_non_image_upload(client: TestClient) -> None:
    response = client.post("/segment/auto", files={"image": ("notes.txt", b"hello", "text/plain")})
    assert response.status_code == 415
    assert response.json()["error"]["code"] == "unsupported_image"


def test_rejects_oversized_upload() -> None:
    small_limit = TestClient(create_app(make_settings(max_upload_bytes=1000)))
    response = small_limit.post("/segment/auto", files={"image": ("desk.jpg", photo_bytes((800, 800)), "image/jpeg")})
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "upload_too_large"


def test_point_segment_adds_mask(client: TestClient, segmented: dict) -> None:
    response = client.post(
        "/segment/point", json={"image_id": segmented["image_id"], "points": [{"x": 200, "y": 150, "positive": True}]}
    )
    assert response.status_code == 200
    mask = response.json()["data"]["mask"]
    x, y, w, h = mask["bbox"]
    assert x < 200 < x + w and y < 150 < y + h


def test_point_outside_photo_is_rejected(client: TestClient, segmented: dict) -> None:
    response = client.post("/segment/point", json={"image_id": segmented["image_id"], "points": [{"x": 999, "y": 10}]})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "point_out_of_bounds"


def test_unknown_image_id_returns_404_envelope(client: TestClient) -> None:
    response = client.post("/cutout", json={"image_id": "nope", "mask_ids": ["x"]})
    assert response.status_code == 404
    assert response.json() == {
        "ok": False,
        "data": None,
        "error": {"code": "image_not_found", "message": "Photo expired or unknown. Please capture it again."},
    }


def test_invalid_body_returns_envelope(client: TestClient) -> None:
    response = client.post("/cutout", json={"image_id": "abc", "mask_ids": [], "cut_style": "jagged"})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "invalid_request"


def test_cutout_returns_transparent_scraps(client: TestClient, segmented: dict) -> None:
    mask_ids = [m["id"] for m in segmented["masks"]]
    response = client.post("/cutout", json={"image_id": segmented["image_id"], "mask_ids": mask_ids, "cut_style": "tight"})
    scraps = response.json()["data"]["scraps"]
    assert [s["mask_id"] for s in scraps] == mask_ids
    scrap = Image.open(io.BytesIO(base64.b64decode(scraps[0]["png_base64"])))
    assert scrap.mode == "RGBA"
    assert scrap.getpixel((0, 0))[3] == 0  # corner outside the ellipse is transparent
    assert scraps[0]["palette"][0] == "#C8B496"  # the photo's flat color


def test_cutout_unknown_mask_is_404(client: TestClient, segmented: dict) -> None:
    response = client.post("/cutout", json={"image_id": segmented["image_id"], "mask_ids": ["missing"]})
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "mask_not_found"


def test_rate_limit_returns_429() -> None:
    limited = TestClient(create_app(make_settings(rate_limit_per_minute=2)))
    codes = [limited.post("/cutout", json={"image_id": "x", "mask_ids": ["y"]}).status_code for _ in range(3)]
    assert codes == [404, 404, 429]
    assert limited.get("/health").status_code == 200  # health is exempt


def test_enrich_returns_metadata_and_palette(client: TestClient) -> None:
    buffer = io.BytesIO()
    scrap = Image.new("RGBA", (50, 50), (0, 0, 0, 0))
    scrap.paste((10, 120, 60, 255), (10, 10, 40, 40))
    scrap.save(buffer, format="PNG")
    response = client.post("/enrich", files={"scrap": ("scrap.png", buffer.getvalue(), "image/png")})
    data = response.json()["data"]
    assert data["type"] == "receipt" and "coffee" in data["tags"]
    assert data["palette"] == ["#0A783C"]  # transparent pixels are ignored


def test_real_providers_without_key_fail_fast() -> None:
    try:
        create_app(make_settings(use_real_providers=True, meta_api_key=None))
    except RuntimeError as exc:
        assert "MODEL_API_KEY" in str(exc)
    else:
        raise AssertionError("expected startup to fail")


def test_api_key_accepts_both_env_var_names(monkeypatch) -> None:  # noqa: ANN001
    from app.config import Settings

    monkeypatch.delenv("META_API_KEY", raising=False)
    monkeypatch.setenv("MODEL_API_KEY", "from-model")
    assert Settings(_env_file=None).meta_api_key == "from-model"
    monkeypatch.delenv("MODEL_API_KEY")
    monkeypatch.setenv("META_API_KEY", "from-meta")
    assert Settings(_env_file=None).meta_api_key == "from-meta"
