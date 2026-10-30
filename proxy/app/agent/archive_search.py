"""`search_archive`: the agent's tool for finding scraps (SPEC 4.6).

The archive lives on the device, so the app sends compact summaries with each
plan request and the search runs over those here. Scoring is simple and
explainable: word overlap with tags / text / description / mood / type, plus an
optional colour match.
"""

import re
from collections.abc import Sequence
from dataclasses import dataclass

DEFAULT_LIMIT = 10
MAX_LIMIT = 20
COLOR_MATCH_DISTANCE = 90.0  # RGB distance under which two colours count as similar

_WORD = re.compile(r"[a-z0-9]+")
_STOPWORDS = frozenset({"a", "an", "the", "and", "or", "of", "for", "with", "in", "on", "my", "to"})
_HEX = re.compile(r"^#?([0-9a-fA-F]{6})$")


@dataclass(frozen=True)
class ScrapSummary:
    id: str
    type: str = "other"
    tags: tuple[str, ...] = ()
    ocr_text: str = ""
    mood: tuple[str, ...] = ()
    description: str = ""
    palette: tuple[str, ...] = ()

    def as_result(self) -> dict[str, object]:
        """What the model sees: enough to judge fit, not raw pixels."""
        return {
            "id": self.id,
            "type": self.type,
            "tags": list(self.tags),
            "mood": list(self.mood),
            "text": self.ocr_text[:120],
            "description": self.description[:160],
            "palette": list(self.palette[:3]),
        }


def search_archive(
    archive: Sequence[ScrapSummary],
    query: str = "",
    tags: Sequence[str] = (),
    types: Sequence[str] = (),
    colors: Sequence[str] = (),
    limit: int = DEFAULT_LIMIT,
) -> list[ScrapSummary]:
    """Best matches first; scraps with no match at all are left out."""
    words = _words(query) | {w for t in tags for w in _words(t)}
    wanted_types = {t.lower() for t in types}
    wanted_colors = [rgb for c in colors if (rgb := _rgb(c)) is not None]
    scored = []
    for index, scrap in enumerate(archive):
        score = _score(scrap, words, wanted_types, wanted_colors)
        if score > 0:
            scored.append((score, -index, scrap))
    scored.sort(reverse=True)
    return [scrap for *_, scrap in scored[: max(1, min(limit, MAX_LIMIT))]]


def _score(
    scrap: ScrapSummary, words: set[str], wanted_types: set[str], wanted_colors: list[tuple[int, int, int]]
) -> float:
    score = 0.0
    tag_words = {w for t in scrap.tags for w in _words(t)}
    mood_words = {w for m in scrap.mood for w in _words(m)}
    text_words = _words(scrap.ocr_text) | _words(scrap.description)
    score += 3 * len(words & tag_words) + 2 * len(words & mood_words) + len(words & text_words)
    if scrap.type in wanted_types or scrap.type in words:
        score += 3
    for color in wanted_colors:
        if any(_distance(color, own) < COLOR_MATCH_DISTANCE for own in map(_rgb, scrap.palette) if own):
            score += 2
    return score


def _words(text: str) -> set[str]:
    return {w for w in _WORD.findall(text.lower()) if w not in _STOPWORDS and len(w) > 1}


def _rgb(color: str) -> tuple[int, int, int] | None:
    match = _HEX.match(color.strip())
    if match is None:
        return None
    value = match.group(1)
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)


def _distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    return sum((x - y) ** 2 for x, y in zip(a, b, strict=True)) ** 0.5
