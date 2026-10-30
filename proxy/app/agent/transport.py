"""Theme Blend agent over the Responses API (keeps the model's reasoning between
tool-call turns via previous_response_id) plus an offline mock planner."""

from collections.abc import Sequence

from openai import OpenAI

from app.agent.archive_search import ScrapSummary, search_archive
from app.agent.layout import TextTransport
from app.agent.planner import INSTRUCTIONS, SEARCH_TOOL, AgentTransport, AgentTurn, BlendPlan, FunctionCall, PlanScrap
from app.config import Settings
from app.providers.meta_client import call_model, log_usage

AGENT_REASONING_EFFORT = "low"  # planning; keeps a plan well under the 20 s target
# Layout is placement arithmetic the backend clamps and de-overlaps anyway; at "low"
# Wonder spent ~1.1k reasoning tokens (billed as output) on it.
LAYOUT_REASONING_EFFORT = "minimal"


def agent_transport(client: OpenAI, settings: Settings) -> AgentTransport:
    def send(items: list[dict], previous_id: str | None, allow_tools: bool) -> AgentTurn:
        kwargs: dict[str, object] = {
            "model": settings.agent_model,
            "instructions": INSTRUCTIONS,
            "input": items,
            "reasoning": {"effort": AGENT_REASONING_EFFORT},
        }
        # Meta's API only supports tool_choice="auto", so once the search budget is
        # spent we stop offering the tool instead of sending tool_choice="none".
        if allow_tools:
            kwargs["tools"] = [SEARCH_TOOL]
        if previous_id:
            kwargs["previous_response_id"] = previous_id
        response = call_model("Agent plan", lambda: client.responses.create(**kwargs))
        log_usage("Agent plan", settings.agent_model, getattr(response, "usage", None))
        calls = tuple(
            FunctionCall(call_id=item.call_id, name=item.name, arguments=item.arguments or "{}")
            for item in response.output
            if getattr(item, "type", None) == "function_call"
        )
        return AgentTurn(response_id=response.id, calls=calls, text=response.output_text or "")

    return send


class MockPlanner:
    """Free, offline stand-in: searches the theme's words and plans the top hits."""

    def plan(self, theme: str, pinned_ids: Sequence[str], archive: Sequence[ScrapSummary]) -> BlendPlan:
        by_id = {s.id: s for s in archive}
        picks = [by_id[i] for i in pinned_ids if i in by_id]
        picks += [s for s in search_archive(archive, query=theme, limit=6) if s not in picks]
        palette = tuple(dict.fromkeys(c for s in picks for c in s.palette[:2]))[:5] or ("#E8DCC4", "#6B4F3A")
        return BlendPlan(
            theme=theme,
            title=theme.title()[:80],
            palette=palette,
            paper="kraft",
            scraps=tuple(PlanScrap(id=s.id, reason=f"Matches '{theme}' (mock)") for s in picks[:6]),
            captions=(f"{theme}.",),
            layout_intent="Largest scrap anchors the top left; the rest cascade diagonally (mock plan).",
            ephemera=({"kind": "stamp", "prompt": f"vintage postage stamp, {theme}"},),
            tool_calls=1,
        )


def layout_transport(client: OpenAI, settings: Settings) -> TextTransport:
    """The layout step is a single JSON answer from the agent model (no tools)."""

    def send(system: str, user: str) -> str:
        response = call_model(
            "Agent layout",
            lambda: client.chat.completions.create(
                model=settings.agent_model,
                messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
                reasoning_effort=LAYOUT_REASONING_EFFORT,
            ),
        )
        log_usage("Agent layout", settings.agent_model, response.usage)
        return response.choices[0].message.content or ""

    return send
