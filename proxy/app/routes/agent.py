"""Theme Blend agent routes (SPEC 4.6). Plan now; build (layout) lands on Day 5."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.agent.archive_search import ScrapSummary
from app.envelope import ApiError, ok
from app.providers import Providers
from app.routes import deps

router = APIRouter(prefix="/agent", tags=["agent"])

MAX_ARCHIVE = 500
MAX_PINNED = 8


class ScrapSummaryIn(BaseModel):
    id: str = Field(min_length=1, max_length=64)
    type: str = Field(default="other", max_length=32)
    tags: list[str] = Field(default_factory=list, max_length=20)
    ocr_text: str = Field(default="", max_length=1000)
    mood: list[str] = Field(default_factory=list, max_length=10)
    description: str = Field(default="", max_length=600)
    palette: list[str] = Field(default_factory=list, max_length=8)

    def to_summary(self) -> ScrapSummary:
        return ScrapSummary(
            id=self.id,
            type=self.type,
            tags=tuple(self.tags),
            ocr_text=self.ocr_text,
            mood=tuple(self.mood),
            description=self.description,
            palette=tuple(self.palette),
        )


class PlanRequest(BaseModel):
    theme: str = Field(min_length=1, max_length=200)
    pinned_ids: list[str] = Field(default_factory=list, max_length=MAX_PINNED)
    archive: list[ScrapSummaryIn] = Field(max_length=MAX_ARCHIVE)


@router.post("/plan")
def plan(body: PlanRequest, models: Annotated[Providers, Depends(deps.providers)]) -> dict[str, Any]:
    if not body.archive:
        raise ApiError(422, "empty_archive", "Scan some scraps first - the agent plans with what's in your archive.")
    result = models.agent.plan(body.theme.strip(), body.pinned_ids, [s.to_summary() for s in body.archive])
    return ok(result.to_json())
