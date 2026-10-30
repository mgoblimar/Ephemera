"""Builds SAM response text the way the API does, for offline tests."""

import re

import numpy as np

# Private encoder, test-only: produces exactly the "!" one-bit payload format SAM sends.
from meta_sam_parser._mask_codec import _encode_raster


def sam_record(object_id: int, box: tuple[int, int, int, int], size: tuple[int, int], raster: np.ndarray) -> str:
    """One object: box is (left, top, right_exclusive, bottom_exclusive) in source pixels."""
    left, top, right, bottom = box
    width, height = size
    rows, cols = raster.shape
    payload = _encode_raster([int(v) for v in raster.flatten()], cols, rows)
    return (
        f"{object_id}<|box;x1={left};y1={top};x2={right - 1};y2={bottom - 1};w={width};h={height}|>"
        f"<|mask;x=0;y=0;data={rows},{cols},{payload}|>"
    )


def sam_line(*records: str) -> str:
    return "<0f>" + ",".join(records)


def full_raster(rows: int = 4, cols: int = 4) -> np.ndarray:
    return np.ones((rows, cols), dtype=np.uint8)


def prompt_object_ids(prompt: str) -> list[int]:
    """Object ids named in a box/point prompt built by build_object_prompt."""
    return [int(i) for i in re.findall(r"(?:^|,|>)(\d+)<\|", prompt.removeprefix("<0f>"))]
