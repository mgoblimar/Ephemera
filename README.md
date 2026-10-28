# EphemeraAI

Tactile digital junk journaling: snap your desk of tickets, receipts, tape and pressed flowers, cut each piece out with SAM 3.1, and compose journal pages with an AI co-designer (Muse Wonder). Concept and ideas by Jennifer Iglesias ([@jbearj](https://github.com/jbearj)). See [SPEC.md](SPEC.md) for the full product spec.

```
app/     Flutter Android app (capture, review, archive)
proxy/   FastAPI proxy: holds Meta API keys, wraps each model behind an adapter
```

## Run the proxy

```bash
cd proxy
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements-dev.txt   # macOS/Linux: .venv/bin/python
cp .env.example .env                                           # keep USE_REAL_PROVIDERS=false while building
.venv/Scripts/python -m uvicorn app.main:create_app --factory --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` lets a phone on the same Wi-Fi reach it. With `USE_REAL_PROVIDERS=false`, every model call is a free, offline mock.

Tests: `.venv/Scripts/python -m pytest`

### Check Muse Wonder tool calling (Day 1)

Put your key in `proxy/.env` as `META_API_KEY=...`, then:

```bash
.venv/Scripts/python scripts/muse_tool_call_check.py
```

It makes two tiny requests and prints PASS/FAIL, latency and token usage.

## Run the app

```bash
cd app
flutter run                                                     # Android emulator (proxy at 10.0.2.2:8000)
flutter run --dart-define=PROXY_URL=http://<your-pc-lan-ip>:8000   # physical phone
```

Tests: `flutter test` · Lint: `flutter analyze`
