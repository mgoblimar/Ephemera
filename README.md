# EphemeraAI

Tactile digital junk journaling. Snap your desk of tickets, receipts, wrappers, stickers and pressed flowers; every piece is found and cut out with its torn edges intact; then an AI co-designer composes themed journal pages from your own scraps, adding stamps and washi tape it draws itself.

Built for the Meta AI hackathon (Indie track). Concept and ideas by Jennifer Iglesias ([@jbearj](https://github.com/jbearj)); built solo. The full product spec, test results and day plan are in [SPEC.md](SPEC.md).

## What it does

- **Scan session.** Add a few photos; Muse Spark finds every piece (each sticker on a sheet separately). Look closer at a wrapper and **Split** it into its logo, lettering and characters. Untick what you don't want, then **Cut & save** once: up to 16 pieces from any number of photos go to SAM 3.1 as one request (₱0.16), cut from the full-resolution photo.
- **Archive wall.** Every scrap is read by Muse Spark in the background: text, dates, places, prices, tags, mood, a one-line description, a **journal prompt** ("Where were you headed on this ride?") and caption ideas. Combined filters (search, vibe, tags, type, colour, split-from, date, status, made by AI). Mark scraps that are glued into a real spread ("Used in a spread", with a note) so the agent leaves them out; remove junk with undo.
- **Theme Blend agent (Muse Wonder).** Type a theme ("cozy cat café, pastel pink"). The agent searches your archive with a tool, then returns a plan: chosen scraps with reasons, a palette, paper, captions and decorations to make. Drop anything, see the cost, Build: **Muse Image** makes the stamps, stickers, tickets and tape (lifted off their background into cut-outs), and the agent lays the page out.
- **Editor and book.** Drag, pinch, rotate and layer scraps; handwritten captions (with ideas from the scraps on the page); freehand pen in five colours; paper styles; undo/redo; PNG export. Journals sit on a shelf as cloth-bound covers and turn like a book.
- **Themes.** "Desk" (warm editorial scrapbook) and "Cozy cat" (pastels, our own cat and paw doodles), switchable from the Journals tab.

## Meta models used

| Job | Model | How |
|---|---|---|
| Find pieces in a photo, split a scrap into design elements | **Muse Spark 1.3** (vision) | Pixel boxes from the photo; boxes are corrected for a measured downward bias |
| Read each scrap: text, entities, tags, mood, description, journal prompt, caption ideas | **Muse Spark 1.3** | One call per scrap, in the background |
| Cut every piece out | **SAM 3.1** | Box prompts; up to 16 pieces per request on a contact sheet; masks applied to the full-size photo |
| Theme Blend: plan (tool calling over the archive) and page layout | **Muse Wonder 1.0** | Responses API with a `search_archive` tool, then a structured layout step |
| Stamps, stickers, tickets, labels, washi tape | **Muse Image 1.0** | Generated on plain white, background removed locally |

Typical costs (₱ at ₱64/USD): finding pieces ~₱0.01 per photo; cutting ₱0.16 per 16 pieces; reading a scrap ~₱0.003; a Theme Blend page ~₱4.5 plus ₱0.64 per decoration.

## Repo layout

```
app/     Flutter Android app (Riverpod; local JSON + PNG storage)
proxy/   FastAPI backend: holds the Meta API key, wraps each model behind an adapter
SPEC.md  product spec, model map, test results, backlog, day plan
```

## Run it

### 1. Backend (proxy)

```bash
cd proxy
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements-dev.txt   # macOS/Linux: .venv/bin/python
cp .env.example .env
```

Edit `proxy/.env`: set `MODEL_API_KEY`, and `USE_REAL_PROVIDERS=true` for real models (`false` runs free offline mocks). For a demo, use the demo profile in `.env.example` (`AGENT_MODEL=muse-wonder-1.0`, `VISION_MODEL=muse-spark-1.3`); the contributor models are cheaper but Meta may train on what you send.

```bash
.venv/Scripts/python -m uvicorn app.main:create_app --factory --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` lets a phone on the same Wi-Fi reach it.

### 2. App

```bash
cd app
flutter pub get
flutter run --dart-define=PROXY_URL=http://<your-pc-lan-ip>:8000
```

On the Android emulator the default `http://10.0.2.2:8000` works without `--dart-define`. Over USB, `adb reverse tcp:8000 tcp:8000` and `PROXY_URL=http://127.0.0.1:8000`.

## Tests and checks

```bash
# proxy (from proxy/): 109 tests, all mocked, free
.venv/Scripts/python -m pytest -q

# app (from app/)
dart format lib test && flutter analyze && flutter test

# live checks (cost credits; see each script's docstring)
.venv/Scripts/python scripts/muse_tool_call_check.py   # Muse Wonder tool calling
.venv/Scripts/python scripts/scan_eval.py test_photos/eval --split sumo --tag run1   # scan quality boards
```

## Privacy

Photos go only to the proxy and the Meta Model API for processing; the proxy keeps them in memory for the scan session (30 min) and does not store them. Scraps and journals live on the device.
