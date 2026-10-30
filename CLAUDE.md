# EphemeraAI — working notes for Claude

Meta AI hackathon project (Indie track). Snap physical junk-journal scraps, cut them out with SAM 3.1, and compose journal pages; an agent (Muse Wonder) will lay out themed pages. **Solo build by the user**; concept and ideas led by Jennifer Iglesias (@jbearj). Product spec, test results and the day plan live in [SPEC.md](SPEC.md) — read its sections 3, 4.1, 5.1 and 8 before planning work.

## Timeline (7 days from 2026-10-29)

| Day | Date | Status |
|---|---|---|
| 1 | Oct 29 | ✅ Scaffold, mocks, Muse Wonder tool-calling check |
| 2 | Oct 30 | ✅ Real SAM + Muse Spark, full-res cutouts, scan session with contact-sheet batching, element Split (quality in backlog) |
| 3 | Oct 31 | ✅ Canvas editor, library, page-flip book; **cut line passed on the tablet** |
| 4 | Nov 1 | ✅ Theme system, live Muse Spark enrichment, Theme Blend plan step (done a day early, Oct 30) |
| 5 | Nov 2 | Morning: agent builds the page. Afternoon: **UI/UX polish pass** (SPEC 4.8) incl. archive filters (SPEC 4.2), then Cozy cat theme if time. P2 only if time. **Feature freeze tonight** |
| 6 | Nov 3 | Demo video only |
| 7 | Nov 4 | Submit + social posts only |

**Where we stopped:** Day 5 afternoon polish done (archive wall + filters, cloth covers, editor corner handle + washi toolbar, scan shimmer/reveal, piece review sheet, app icon + splash). Scan tuning started (SPEC 4.1b "Scan tuning"): pixel-coordinate boxes, stricter detect/split prompts, solidity junk filter, `scripts/scan_eval.py` test run. `AGENT_MODEL=muse-wonder-1.0` is now set in `.env` and tested on the emulator (Oct 30): after limiting the planner to one parallel search round and running layout at `minimal`, plan ~25 s + layout ~7 s, ~₱4.5 per page (was ~80 s + 11 s, ~₱7). Cozy cat theme built (palette button on Journals; choice saved in settings.json). **Next:** more scan tuning (glossy "photo" elements, shadows in boxes) only if time.

## Repo layout

```
SPEC.md      product spec, model map (5.1), test results, backlog, day plan (8)
proxy/       FastAPI backend: holds Meta API keys, wraps each model behind an adapter
  app/providers/   base.py (protocols + PixelBox/DetectedItem/Mask), mock.py, real.py,
                   sam.py (SAM client + fast mask parser), detector.py (Muse Spark prompts),
                   meta_client.py (OpenAI SDK client, error mapping, timing logs)
  app/routes/      segment.py (old per-photo flow), scan.py (detect / split / cut), enrich.py (mock)
  app/contact_sheet.py  packs ≤16 pieces from many photos into one SAM request
  app/imaging.py   upload validation, cut styles, cut_from_original, fill_holes, drop_islands, palette
  scripts/         muse_tool_call_check.py, segment_photo_check.py, scan_eval.py (live checks, cost credits)
app/         Flutter Android app (Riverpod 2.x, local JSON + PNG storage)
  lib/features/scan/      scan session (main capture flow) + Split
  lib/features/editor/    page canvas, editor, undo/redo history, handwriting fonts
  lib/features/library/   journal shelf + book (3D page turn)
  lib/features/capture/   old review screen (tap-to-add; kept but unreachable), shared pickers
```

## Commands

```bash
# proxy (from proxy/)
.venv/Scripts/python -m pytest -q                       # 92 tests, all mocked, free
.venv/Scripts/python -m uvicorn app.main:create_app --factory --port 8000          # mock mode
USE_REAL_PROVIDERS=true .venv/Scripts/python -m uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8100   # real models

# app (from app/)
dart format lib test && flutter analyze && flutter test  # 67 tests
adb reverse tcp:8100 tcp:8100
flutter run -d R52X807YBTD --dart-define=PROXY_URL=http://127.0.0.1:8100        # tablet over USB
```

## Meta models and cost (user is cost-sensitive — quote ₱ at ₱64/USD)

| Job | Setting | Testing profile | Price |
|---|---|---|---|
| Find items / split elements / OCR | `VISION_MODEL` | `muse-spark-1.3-contributor` (~₱0.01 per photo) | standard Spark $1.25/$4.25 per 1M |
| Theme Blend Agent | `AGENT_MODEL` | contributor Spark while building; `muse-wonder-1.0` for demo (~₱3/plan) | Wonder $4/$20 per 1M; **reasoning tokens bill as output** |
| Cutouts | `SAM_MODEL` = `sam-3.1` | no contributor mode | $0.0025 (₱0.16) per request, up to 16 objects |
| Generated ephemera | `IMAGE_MODEL` = `muse-image-1.0` | no contributor mode | $0.01 per image |

- **Always state the cost before any live API call and get the user's OK.** Live checks so far cost under ₱2 total.
- Contributor mode: Meta may train on inputs — only use test photos the user is fine sharing; switch to standard models for the demo.
- Key lives in `proxy/.env` as `MODEL_API_KEY` (or `META_API_KEY`). Never read or print it.

## Key technical decisions (don't relitigate)

- **SAM 3.1 has no "segment everything".** Auto-detect = Muse Spark boxes → SAM box prompts (Plan A, default). Plan B (concept words) is worse; kept as `AUTO_DETECT_STRATEGY=concepts`.
- **Models see a 1536px copy; cutouts are cut from the full-size original** (≤3072px upload). Holes are filled and small islands dropped before cut styles.
- **Scan session:** detect is cheap (Spark only); cut packs ≤16 chosen pieces from any photos onto one contact sheet → **one** billed SAM request (verified `images_processed=1`).
- SAM output parsing uses our fast regex parser + `meta_sam_parser._mask_codec._decode_raster` (internal, single pass); `meta-sam-parser==0.1.0` is **pinned** for that reason. Masks are binary and lower-res than the box.
- Muse Wonder makes **3–4 parallel tool calls per turn**; every tool call needs its own tool response. Use the **Responses API** for the agent loop (keeps reasoning across turns).
- Detection uses `reasoning_effort="minimal"` (≈6s); `low` was ~15s.
- **Spark boxes are asked for in pixels with the image size in the prompt** (0–1000 grid was up to 3% off on portrait photos). Cut-outs with mask solidity < 0.6 are dropped as `rough`.
- **Meta's Responses API only accepts `tool_choice="auto"`** — to stop tool use, omit `tools` instead (agent transport does this when the 8-search budget is spent).
- Element Split works for logos/lettering; loose boxes and busy backgrounds are poor → **backlog** (SPEC 4.1b). Refinement taps / edge snapping / "Find…" are **parked** (SPEC 4.1c).

## Archive filters (SPEC 4.2)

Combined filters: search text, vibe/mood, tags, type, colour, split-from, date added. Next iteration: `physical_status` (available / used / reserved) so scraps glued into real spreads can be filtered out and skipped by the agent.

## UI direction

Junk-journal desk feel; default theme **Desk** (warm editorial scrapbook). Themes are swappable `ThemeExtension` token sets (SPEC 4.8). A cute **Cozy cat** theme is wanted, mofusand-*inspired* in mood only: never use mofusand characters, art or name (copyrighted).

## Gotchas (learned the hard way)

- **Python on Windows writes cp1252 by default** — always `read_text/write_text(encoding="utf-8")` (or `PYTHONUTF8=1`) when editing files containing ₱ … ↳. A crash mid-write truncated a file once.
- The user may run their **own mock proxy on port 8000** (0.0.0.0); the real-model proxy for the tablet runs on **8100** via `adb reverse` to avoid clashing.
- "Lost connection to device" from `flutter run` usually just means the app went to background — not a crash.
- Kotlin "Could not close incremental caches" during Android builds is a harmless Windows cross-drive warning.
- Flutter widget tests: file I/O started inside the fake-async zone never completes → trigger the action **inside `tester.runAsync`** and poll with `tester.pump()` (see scan/editor tests). Set `useGoogleFonts = false` in tests.
- Two `IndexedStack` tabs with FABs need distinct `heroTag`s; grids need `ZeroWidthGuard` (zero width during some transitions).
- Gesture end must commit the **latest** gesture value, not `widget.element` (move + release can share a frame).
- Don't stop user processes (e.g. Stop-Process on Java/Gradle daemons is blocked) — tell the user instead.
- Photos saved from Messenger are ~720px; the camera gives full res. Glare through plastic sleeves ruins edges.

## Working agreements with the user

- Commit only when asked (they usually say "commit"); conventional commits ending with the `Co-Authored-By` line. They push themselves or ask.
- Verify on the tablet (R52X807YBTD) for anything user-facing; check saved scraps via `adb exec-out run-as com.ephemeraai.ephemera_ai cat app_flutter/archive/...`.
- Keep explanations short and in plain language; give peso costs; offer a recommendation rather than a menu.
