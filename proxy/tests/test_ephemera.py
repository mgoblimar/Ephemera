import base64
import io

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from app.envelope import ApiError
from app.ephemera import ephemera_prompt, lift_off_background


def _alpha(image: Image.Image) -> np.ndarray:
    return np.asarray(image)[:, :, 3]


def test_prompt_names_the_kind_theme_colours_and_plain_background() -> None:
    prompt = ephemera_prompt("stamp", "lemon tart", ["#F2C14E", "#6B4F3A"])

    assert "postage stamp" in prompt and "lemon tart" in prompt
    assert "#F2C14E" in prompt
    assert "plain pure white background" in prompt


def test_background_is_removed_but_white_inside_the_design_stays() -> None:
    image = Image.new("RGB", (300, 200), "white")
    draw = ImageDraw.Draw(image)
    draw.rectangle((50, 40, 250, 160), fill=(30, 60, 120))  # a dark label...
    draw.rectangle((90, 80, 210, 120), fill="white")  # ...with a white panel inside

    cut = lift_off_background(image)

    assert abs(cut.width - 201) <= 6 and abs(cut.height - 121) <= 6  # cropped to the label
    alpha = _alpha(cut)
    assert alpha[0, 0] < 30  # outside corner is transparent
    assert alpha[cut.height // 2, cut.width // 2] > 220  # the white panel is kept


def test_off_white_paper_background_is_removed_too() -> None:
    image = Image.new("RGB", (200, 200), (238, 232, 220))
    ImageDraw.Draw(image).ellipse((40, 40, 160, 160), fill=(200, 80, 90))

    alpha = _alpha(lift_off_background(image))

    assert alpha[0, 0] < 30 and alpha[alpha.shape[0] // 2, alpha.shape[1] // 2] > 220


def test_a_blank_picture_is_an_error() -> None:
    with pytest.raises(ApiError):
        lift_off_background(Image.new("RGB", (100, 100), "white"))


def test_ephemera_route_returns_a_cut_out_png(client: TestClient) -> None:
    response = client.post(
        "/agent/ephemera", json={"kind": "stamp", "prompt": "sunny lemons", "palette": ["#F2C14E"]}
    )

    assert response.status_code == 200
    data = response.json()["data"]
    png = Image.open(io.BytesIO(base64.b64decode(data["png_base64"])))
    assert png.mode == "RGBA" and (png.width, png.height) == (data["width"], data["height"])
    assert data["kind"] == "stamp" and data["palette"]  # palette read from the result


def test_ephemera_route_rejects_unknown_kinds(client: TestClient) -> None:
    response = client.post("/agent/ephemera", json={"kind": "rocket", "prompt": "x"})

    assert response.status_code == 422
