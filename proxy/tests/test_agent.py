import json

from fastapi.testclient import TestClient

from app.agent.archive_search import ScrapSummary, search_archive
from app.agent.planner import MAX_TOOL_CALLS, AgentTurn, BlendPlanner, FunctionCall, parse_plan

ARCHIVE = [
    ScrapSummary(id="r1", type="receipt", tags=("coffee", "cafe"), ocr_text="Cafe Lumiere 09:42", mood=("cozy",), palette=("#6B4F3A",)),
    ScrapSummary(id="f1", type="botanical", tags=("flower", "brown"), mood=("calm",), palette=("#8B5A2B",)),
    ScrapSummary(id="t1", type="ticket", tags=("bus", "travel"), ocr_text="P20.00", palette=("#F2CC8F",)),
    ScrapSummary(id="w1", type="wrapper", tags=("cookies",), description="blue cookie wrapper", palette=("#1E6FB8",)),
]


def test_search_ranks_tag_matches_above_text_matches() -> None:
    results = search_archive(ARCHIVE, query="cozy coffee morning")

    assert [s.id for s in results] == ["r1"]


def test_search_by_type_and_colour() -> None:
    assert [s.id for s in search_archive(ARCHIVE, query="", types=["ticket"])] == ["t1"]
    assert "f1" in [s.id for s in search_archive(ARCHIVE, query="", colors=["#8A5A2C"])]


def test_search_with_no_match_returns_nothing() -> None:
    assert search_archive(ARCHIVE, query="spaceship") == []


def _call(call_id: str, query: str) -> FunctionCall:
    return FunctionCall(call_id=call_id, name="search_archive", arguments=json.dumps({"query": query}))


class ScriptedModel:
    """Plays back model turns and records what it was sent."""

    def __init__(self, turns: list[AgentTurn]) -> None:
        self.turns = turns
        self.sent: list[tuple[list[dict], str | None, bool]] = []

    def __call__(self, items: list[dict], previous_id: str | None, allow_tools: bool) -> AgentTurn:
        self.sent.append((items, previous_id, allow_tools))
        return self.turns[len(self.sent) - 1]


def test_every_parallel_call_gets_its_own_result_and_plan_uses_found_scraps() -> None:
    plan_json = json.dumps(
        {
            "title": "Slow Sunday",
            "palette": ["#6B4F3A", "#E8DCC4", "not-a-colour"],
            "paper": "kraft",
            "scraps": [{"id": "r1", "reason": "the cafe"}, {"id": "w1", "reason": "never searched"}, {"id": "ghost"}],
            "captions": ["9:42, still sleepy"],
            "layout_intent": "Receipt top left.",
            "ephemera": [{"kind": "stamp", "prompt": "coffee stamp"}, {"kind": "rocket", "prompt": "x"}],
        }
    )
    model = ScriptedModel(
        [
            AgentTurn("resp1", (_call("c1", "coffee"), _call("c2", "cozy"), _call("c3", "flower")), ""),
            AgentTurn("resp2", (), plan_json),
        ]
    )

    plan = BlendPlanner(model).plan("slow sunday cafe", [], ARCHIVE)

    outputs, previous_id, _ = model.sent[1]
    assert previous_id == "resp1"
    assert [o["call_id"] for o in outputs] == ["c1", "c2", "c3"]
    assert [s.id for s in plan.scraps] == ["r1"]  # w1 never returned by a search, ghost unknown
    assert plan.palette == ("#6B4F3A", "#E8DCC4")
    assert plan.paper == "kraft"
    assert [e["kind"] for e in plan.ephemera] == ["stamp"]
    assert plan.tool_calls == 3


def test_tool_calls_beyond_the_limit_are_answered_with_an_error() -> None:
    many = tuple(_call(f"c{i}", "coffee") for i in range(MAX_TOOL_CALLS + 2))
    model = ScriptedModel([AgentTurn("resp1", many, ""), AgentTurn("resp2", (), "{}")])

    plan = BlendPlanner(model).plan("coffee", [], ARCHIVE)

    outputs, _, allow_tools = model.sent[1]
    assert len(outputs) == MAX_TOOL_CALLS + 2  # every call still answered
    assert "limit" in json.loads(outputs[-1]["output"])["error"]
    assert allow_tools is False
    assert plan.tool_calls == MAX_TOOL_CALLS


def test_pinned_scraps_can_be_planned_without_being_searched() -> None:
    model = ScriptedModel([AgentTurn("resp1", (), json.dumps({"scraps": [{"id": "t1", "reason": "pinned"}]}))])

    plan = BlendPlanner(model).plan("anything", ["t1"], ARCHIVE)

    assert [s.id for s in plan.scraps] == ["t1"]


def test_unparseable_plan_falls_back_to_defaults() -> None:
    plan = parse_plan("I can't decide", "rainy kyoto", {}, 0)

    assert plan.title == "rainy kyoto" and plan.scraps == () and plan.paper == "cream"


def test_plan_route_with_mock_agent(client: TestClient) -> None:
    archive = [{"id": s.id, "type": s.type, "tags": list(s.tags), "ocr_text": s.ocr_text, "palette": list(s.palette)} for s in ARCHIVE]

    data = client.post("/agent/plan", json={"theme": "coffee cafe", "archive": archive}).json()["data"]

    assert data["scraps"][0]["id"] == "r1"
    assert data["palette"] and data["captions"]


def test_plan_route_rejects_an_empty_archive(client: TestClient) -> None:
    response = client.post("/agent/plan", json={"theme": "coffee", "archive": []})

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "empty_archive"


def test_transport_never_sends_tool_choice_and_drops_tools_when_budget_is_spent() -> None:
    from types import SimpleNamespace

    from app.agent.transport import agent_transport
    from tests.conftest import make_settings

    sent: list[dict] = []

    class FakeResponses:
        def create(self, **kwargs: object) -> SimpleNamespace:
            sent.append(kwargs)
            return SimpleNamespace(id="r", output=[], output_text="{}", usage=None)

    client = SimpleNamespace(responses=FakeResponses())
    send = agent_transport(client, make_settings())  # type: ignore[arg-type]

    send([{"role": "user", "content": "x"}], None, True)
    send([], "r", False)

    assert all("tool_choice" not in kwargs for kwargs in sent)  # Meta only accepts "auto"
    assert "tools" in sent[0] and "tools" not in sent[1]
    assert sent[1]["previous_response_id"] == "r"
