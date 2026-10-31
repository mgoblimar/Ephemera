"""Theme Blend agent, plan step (SPEC 4.6): theme in, approvable Blend Plan out.

The model gets one tool, `search_archive`, and usually calls it several times
in parallel with different phrasings. Every call gets its own result (the API
rejects a turn that leaves one unanswered), at most MAX_TOOL_CALLS run, and the
final JSON plan may only use scraps the searches actually returned.
"""

import json
import logging
import re
from collections.abc import Callable, Sequence
from dataclasses import asdict, dataclass

from app.agent.archive_search import ScrapSummary, search_archive
from app.providers.detector import extract_json

logger = logging.getLogger(__name__)

MAX_TOOL_CALLS = 8
MAX_TURNS = 6
MAX_SEARCH_ROUNDS = 1  # one parallel round, then the plan: every extra turn costs Wonder ~15-50 s
MAX_PLAN_SCRAPS = 15  # the app shows them all ticked; the user unticks extras
MAX_CAPTIONS = 3
MAX_EPHEMERA = 4
PAPERS = ("cream", "kraft", "dots")
EPHEMERA_KINDS = ("stamp", "tape", "label", "ticket", "sticker")
_HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")

SEARCH_TOOL = {
    "type": "function",
    "name": "search_archive",
    "description": "Search the user's archive of cut-out journal scraps. Call it several times with different "
    "phrasings, objects, moods or colours to find everything that fits the theme.",
    "parameters": {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "Words to match against tags, text, mood and descriptions."},
            "types": {"type": "array", "items": {"type": "string"}, "description": "Scrap types, e.g. ticket, wrapper."},
            "colors": {"type": "array", "items": {"type": "string"}, "description": "Hex colours like #8B5A2B."},
            "limit": {"type": "integer", "description": "Max results, default 10."},
        },
        "required": ["query"],
    },
}

INSTRUCTIONS = f"""You are Theme Blend, a junk-journal page designer working with the user's real scraps.
1. Search the archive once: make 3-5 search_archive calls together in your first reply (different phrasings: objects,
moods, colours). You won't get to search again, so cover the theme in that one go.
2. Choose 6-{MAX_PLAN_SCRAPS} scraps that could belong on this page, best fit first; the user unticks the ones they
skip, so offer every good candidate. Always include pinned scraps.
3. Reply with only this JSON:
{{"title": short page title,
 "palette": 4-6 hex colours that harmonise with the theme and chosen scraps,
 "paper": one of {", ".join(PAPERS)},
 "scraps": [{{"id": scrap id from search results, "reason": one short line}}],
 "captions": up to {MAX_CAPTIONS} short handwritten captions for the page,
 "layout_intent": one sentence on how the page is arranged,
 "ephemera": up to {MAX_EPHEMERA} decorations to generate: [{{"kind": one of {", ".join(EPHEMERA_KINDS)}, "prompt": "..."}}]}}"""


@dataclass(frozen=True)
class FunctionCall:
    call_id: str
    name: str
    arguments: str


@dataclass(frozen=True)
class AgentTurn:
    response_id: str
    calls: tuple[FunctionCall, ...]
    text: str


# (input items, previous response id, tools allowed) -> the model's next turn.
AgentTransport = Callable[[list[dict], str | None, bool], AgentTurn]


@dataclass(frozen=True)
class PlanScrap:
    id: str
    reason: str


@dataclass(frozen=True)
class BlendPlan:
    theme: str
    title: str
    palette: tuple[str, ...]
    paper: str
    scraps: tuple[PlanScrap, ...]
    captions: tuple[str, ...]
    layout_intent: str
    ephemera: tuple[dict[str, str], ...]
    tool_calls: int

    def to_json(self) -> dict[str, object]:
        data = asdict(self)
        return {**data, "scraps": [asdict(s) for s in self.scraps]}


class BlendPlanner:
    def __init__(self, transport: AgentTransport) -> None:
        self._transport = transport

    def plan(self, theme: str, pinned_ids: Sequence[str], archive: Sequence[ScrapSummary]) -> BlendPlan:
        by_id = {s.id: s for s in archive}
        seen = {i: by_id[i] for i in pinned_ids if i in by_id}  # scraps the plan may use
        pinned = [by_id[i].as_result() for i in pinned_ids if i in by_id]
        prompt = f"Theme: {theme}\nPinned scraps (must use): {json.dumps(pinned)}\nArchive size: {len(archive)} scraps."
        turn = self._transport([{"role": "user", "content": prompt}], None, True)
        used = 0
        for rounds in range(1, MAX_TURNS + 1):
            if not turn.calls:
                break
            outputs = []
            for call in turn.calls:
                if used < MAX_TOOL_CALLS:
                    result = self._run_tool(call, archive, seen)
                    used += 1
                else:
                    result = {"error": "Search limit reached. Write the plan now with what you found."}
                outputs.append({"type": "function_call_output", "call_id": call.call_id, "output": json.dumps(result)})
            allow_tools = used < MAX_TOOL_CALLS and rounds < MAX_SEARCH_ROUNDS
            turn = self._transport(outputs, turn.response_id, allow_tools)
        logger.info("Agent plan finished after %d tool calls", used)
        return parse_plan(turn.text, theme, seen, used)

    def _run_tool(self, call: FunctionCall, archive: Sequence[ScrapSummary], seen: dict[str, ScrapSummary]) -> object:
        if call.name != "search_archive":
            return {"error": f"Unknown tool {call.name}"}
        try:
            args = json.loads(call.arguments or "{}")
        except json.JSONDecodeError:
            return {"error": "Arguments were not valid JSON."}
        results = search_archive(
            archive,
            query=str(args.get("query", "")),
            types=[str(t) for t in args.get("types", []) if isinstance(t, str)],
            colors=[str(c) for c in args.get("colors", []) if isinstance(c, str)],
            limit=int(args.get("limit", 10)) if str(args.get("limit", "")).isdigit() else 10,
        )
        seen.update({s.id: s for s in results})
        return {"results": [s.as_result() for s in results]}


def parse_plan(reply: str, theme: str, seen: dict[str, ScrapSummary], tool_calls: int) -> BlendPlan:
    """Validate the model's plan; anything unusable is dropped or defaulted."""
    data = extract_json(reply)
    if not isinstance(data, dict):
        logger.warning("Agent plan was not JSON: %.200s", reply)
        data = {}
    scraps: list[PlanScrap] = []
    for raw in _list(data.get("scraps")):
        if isinstance(raw, dict) and raw.get("id") in seen and raw["id"] not in {s.id for s in scraps}:
            scraps.append(PlanScrap(id=raw["id"], reason=str(raw.get("reason", ""))[:160]))
    paper = data.get("paper")
    return BlendPlan(
        theme=theme,
        title=str(data.get("title") or theme)[:80],
        palette=tuple(c for c in _list(data.get("palette")) if isinstance(c, str) and _HEX.match(c))[:6],
        paper=paper if paper in PAPERS else "cream",
        scraps=tuple(scraps[:MAX_PLAN_SCRAPS]),
        captions=tuple(str(c)[:80] for c in _list(data.get("captions")) if isinstance(c, str) and c.strip())[:MAX_CAPTIONS],
        layout_intent=str(data.get("layout_intent", ""))[:240],
        ephemera=tuple(
            {"kind": e["kind"], "prompt": str(e.get("prompt", ""))[:200]}
            for e in _list(data.get("ephemera"))
            if isinstance(e, dict) and e.get("kind") in EPHEMERA_KINDS
        )[:MAX_EPHEMERA],
        tool_calls=tool_calls,
    )


def _list(value: object) -> list[object]:
    return value if isinstance(value, list) else []
