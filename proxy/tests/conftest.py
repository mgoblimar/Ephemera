import io

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.main import create_app


def make_settings(**overrides: object) -> Settings:
    base: dict[str, object] = {"use_real_providers": False, "rate_limit_per_minute": 1000}
    return Settings(_env_file=None, **{**base, **overrides})


def photo_bytes(size: tuple[int, int] = (400, 300), color: tuple[int, int, int] = (200, 180, 150), fmt: str = "JPEG") -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, color).save(buffer, format=fmt)
    return buffer.getvalue()


@pytest.fixture
def client() -> TestClient:
    return TestClient(create_app(make_settings()))


@pytest.fixture
def segmented(client: TestClient) -> dict:
    # PNG keeps the flat color exact, so palette assertions are deterministic.
    response = client.post("/segment/auto", files={"image": ("desk.png", photo_bytes(fmt="PNG"), "image/png")})
    assert response.status_code == 200
    return response.json()["data"]
