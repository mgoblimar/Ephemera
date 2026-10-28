# EphemeraAI — Product & Technical Spec

**Tactile Digital Junk Journaling Studio**
Meta AI Hackathon · Theme: *Build for Your World* (Indie Track)
Team: solo build · Concept & ideas led by Jennifer Iglesias ([@jbearj](https://github.com/jbearj)) · **7 days remaining** (as of 2026-10-29): 5 build days, 1 demo-video day, 1 submission & social day
Deliverables: working Android demo, demo video, public repo

---

## 1. Problem & Vision

Physical junk journaling depends on organic, irregular materials: torn tickets, pressed flowers, deckle-edged paper, washi tape, magazine clippings, stickers, wrappers and handwritten notes. Digital collage apps flatten all of this into rigid, sterile graphics. Digitizing keepsakes today means flatbed scanning and lassoing them by hand with a pen tool.

EphemeraAI is a mobile-first Flutter studio that turns physical ephemera into a personal digital archive and then into journal pages. An **agent** helps compose those pages: it blends archived scraps around a theme, fills gaps with generated ephemera, and follows the style of the user's existing physical journals.

**One-line pitch:** Snap your desk, keep every scrap with its torn edges intact, and let an AI co-designer turn your archive into themed journal pages that look like *your* journal.

## 2. Users & Core Jobs

| User | Job to be done |
|---|---|
| Junk journaler with a physical stash | "Digitize my scraps without tedious cutting, and keep them looking real." |
| Journaler with existing physical journals | "Bring my old journals into the app, and have new pages match my style." |
| Busy or blocked creator | "Give me a themed starting page from what I already have, then let me tweak it." |

## 3. Scope & Priorities

The hero flow that must never break is **Snap → Cutout → Collage**. Everything else layers on top of it.

With 7 days left, the scope is tiered so that each tier is demoable on its own.

| Priority | Feature | Notes |
|---|---|---|
| **P0** | Capture (camera + gallery) | Android |
| **P0** | SAM 3.1 extraction: auto-detect all + tap to add | Transparent PNG cutouts that keep edges. Multi-point refine is P1 |
| **P0** | Cut styles: Tight / Sticker border / Keep margin | See 4.1; cheap because it's mask post-processing, not a model call |
| **P0** | Scrap Archive (local) | Grid + tags. Filters beyond type/tag are P1 |
| **P0** | Single-page canvas editor | Move/scale/rotate/z-order, text with handwriting fonts, undo/redo, PNG export |
| **P0** | Journals (books) with page-flip UI | Multiple books; use an existing page-curl package, no custom shader |
| **P1** | Muse Spark OCR + metadata enrichment | Text, dates and places from scraps |
| **P1** | **Theme Blend Agent** (Muse Wonder), `search_archive` tool | Plan → approve → build |
| **P1** | Freehand drawing | Simple pen strokes |
| **P2** | Agent `generate_ephemera` tool (Muse Image) | Stamps, tape strips, labels |
| **P2** | Journal prompts & captions | Reuses the enrichment call; cheap if OCR works |
| **Stretch** | Import an existing physical journal: **Style Profile only** | One Muse Spark call over page photos, fed to the agent |
| Post-hackathon | Journal import: re-extract scraps + read-only digital copy | Kept in the spec (4.7) as the roadmap |
| Post-hackathon | Cloud sync + accounts | |
| Post-hackathon | Aging filters, agent recolor/tint | |

**Cut line:** by the end of **Day 3** the hero flow (P0) must work end-to-end on a real device. If it doesn't, P2 and Stretch are dropped and Days 4–5 go to P0 polish plus the agent with `search_archive` only. Generated ephemera is the first P1/P2 item cut; the import is the stretch goal and starts only after the agent builds pages end-to-end.

## 4. Feature Specs

### 4.1 Capture & Extraction (P0)

**Flow**
1. The user takes a photo or picks one from the gallery. Hint shown: "Lay items flat on a contrasting surface."
2. The app uploads the image to the proxy, which calls **SAM 3.1 automatic mask generation**.
3. The Review screen overlays every candidate mask, each with a checkbox. The user can:
   - **Keep or discard** each candidate.
   - **Tap** an uncovered area to add a new mask (point prompt).
   - **Refine** a mask with extra positive or negative tap points.
4. Before saving, the user picks a **cut style** (a default for all scraps, overridable per scrap, with a live preview):
   - **Tight:** cut exactly along the object's edge. Best for deckle paper and botanicals.
   - **Sticker border:** cut along the edge, then add a solid white outline (S/M/L), like a die-cut sticker.
   - **Keep margin:** grow the cut outward by a few millimeters (S/M/L) so a sliver of the original desk or background stays around the object, like a scrap cut roughly with scissors.

   Implementation: these are mask post-processing on the proxy (dilate the mask by N px; for the sticker style, fill the dilated ring white). They work the same whether SAM returns hard or soft edges.
5. On **Save**, each kept mask becomes a **Scrap**: a cropped RGBA PNG with a 1–2 px feathered alpha so deckle edges and translucent tape stay intact.
6. The scraps land in the Archive under a new "Capture" group, and enrichment (4.3) runs in the background.

**Acceptance criteria**
- A photo with 3–6 items yields at least one usable cutout per item without manual tapping in most cases.
- Translucent washi tape keeps partial alpha, not a hard 0/1 mask (where SAM's output allows it).
- Tap-to-add returns a mask in under 3 s on demo Wi-Fi.
- Masks smaller than 1% of the image area are filtered out as noise.

### 4.2 Scrap Archive (P0)

- Grid of every scrap with filters: **type** (ticket, receipt, botanical, tape, paper, sticker, note, other), **tags**, **dominant color**, **date**, **source** (capture vs. imported journal vs. generated).
- Text search over OCR text and tags (needs P1 enrichment; tags work without it).
- Scrap detail view: image, OCR text, tags (editable), palette swatches, source photo.
- Long-press to multi-select, then "Add to page" or "Blend with agent."

### 4.3 Enrichment: OCR & Context (P1, Muse Spark)

For each new scrap the proxy calls Muse Spark (multimodal) and stores structured metadata:

```json
{
  "type": "receipt",
  "ocr_text": "Café Lumière · 2x flat white · 14/03/2026 09:42",
  "entities": { "date": "2026-03-14", "place": "Café Lumière", "time": "09:42" },
  "tags": ["coffee", "morning", "cafe"],
  "mood": ["cozy", "quiet"],
  "palette": ["#E8DCC4", "#6B4F3A", "#2F2F2F"],
  "description": "Faded thermal café receipt with a coffee ring"
}
```

The palette is computed locally on the proxy (k-means over the opaque pixels), not by the LLM.

**Journal prompts & captions:** on a page or a scrap selection, Muse Spark returns 3 reflective prompts plus 3 short captions grounded in the OCR'd context (e.g. *"What were you thinking about over that 9:42 flat white?"*). Tapping a suggestion inserts it as a text element.

### 4.4 Journals & Book UI (P0)

- **Library shelf:** the user's books (journals), each with a cover (color/texture plus title), shown as spines or covers.
- **Book view:** a realistic two-page spread with a **page-curl flip animation** (drag or swipe to flip, tap the edge to turn). Pages render as thumbnails while flipping and at full resolution at rest.
- Editing happens **one page at a time**: tap a page to open the Canvas Editor; closing it returns to the book at that page.
- Add, delete and reorder pages. Imported journal pages (4.7) appear as **read-only** pages marked with a small "scanned" ribbon.

**Acceptance:** the flip runs at 60 fps on a mid-range Android device with 10+ pages, and books persist across app restarts.

### 4.5 Canvas Editor (P0)

Single page with a fixed aspect ratio (A5 portrait, 1:1.414) and a paper background chosen from a small texture set.

| Tool | Behavior |
|---|---|
| Transform | Drag, pinch-scale, two-finger rotate; snapping off by default |
| Layering | Bring forward/back, to front/back; layer list sheet |
| Text | Handwriting-style fonts (3–5 bundled Google Fonts, e.g. Caveat, Homemade Apple, Reenie Beanie), color, size |
| Freehand | Pen with 3 widths and color picker; strokes are elements (movable, deletable) |
| History | Undo/redo stack (≥ 50 steps), command pattern over immutable page state |
| Export | Page → PNG at 2× resolution, saved to the gallery or shared via the share sheet |
| Insert | From the Archive (bottom sheet), from a prompt suggestion, from generated ephemera |

### 4.6 Theme Blend Agent (P1, Muse Wonder)

The headline agentic feature: it composes a themed page from the archive and generates whatever ephemera is missing.

**Inputs**
- A free-text **theme** (e.g. *"rainy Kyoto trip, moody greens, quiet"*), and/or
- **Pinned scraps** the agent must use.
- (P2) The active **Style Profile** from imported journals.

**Interaction model: Plan → Approve → Build**
1. **Plan:** the agent calls its tools and returns a structured **Blend Plan**:
   - Chosen scraps from the archive (each with a one-line rationale)
   - Ephemera to generate (each with a prompt)
   - Palette (4–6 hex colors) and paper background
   - Layout intent (e.g. "diagonal flow, ticket anchors top-left, tape bridging the botanicals")
   - Caption and prompt text
2. **Approve:** the user reviews the plan as cards and can remove or swap scraps, toggle generation items, edit captions, then **Build**. A "Regenerate plan" option exists.
3. **Build:** the proxy runs the generations, then the layout step returns element placements, and the app renders a new page. The page is fully editable afterwards.

**Agent tools (MVP)**

| Tool | Signature (sketch) | Purpose |
|---|---|---|
| `search_archive` | `(query: str, tags?: [str], colors?: [hex], types?: [str], limit=20) → [ScrapSummary]` | Find matching scraps by OCR text, tags, palette distance and type |
| `generate_ephemera` | `(kind: stamp\|tape\|label\|ticket\|sticker, prompt: str, palette: [hex]) → Scrap` | Muse Image call; result is cut out (SAM or alpha matte) and saved to the Archive with `source=generated` |

Layout is not a tool. It is a final structured-output step: Muse Wonder receives the scrap sizes plus the plan and returns `[{scrap_id, x, y, scale, rotation, z}]` in normalized page coordinates. The app clamps and validates the result.

**Guardrails**
- At most 8 tool calls per plan (token cost and latency) and at most 4 generations per build (latency; images cost only $0.01 each). Each `generate_ephemera` call may request `n=2` variants so the user can pick one in the plan cards.
- The agent only references scrap IDs returned by `search_archive`; unknown IDs are dropped.
- If the archive has fewer than 3 relevant scraps, the plan says so and leans on generation.
- Progress is streamed to the UI ("Searching archive… Found 7 botanicals… Planning layout…").

**Acceptance:** a theme prompt against an archive of 20 or more scraps yields a plan in under 20 s and a built page in under 60 s, and the page is visibly on-theme in palette and content.

### 4.7 Import Existing Journal (Stretch: Style Profile only; rest post-hackathon)

For the hackathon, only output 3 (Style Profile) is in scope, as a stretch goal. Outputs 1 and 2 are the post-hackathon roadmap.

The user photographs pages of a physical journal and imports them into a book. Each page goes through three outputs:

1. **Digital copy:** perspective-corrected page image stored as a read-only page in a chosen book.
2. **Re-extract scraps:** SAM auto-masks on the page, then the user keeps or discards the cutouts (same Review UI as 4.1). Kept scraps join the Archive with `source=imported`.
3. **Style Profile:** Muse Spark analyzes all imported pages together and returns:

```json
{
  "themes": ["travel", "botanical", "café culture"],
  "palette": ["#C9B79C", "#7A8B6F", "#3E3A36", "#D9A5A0"],
  "density": "dense",
  "layering": "heavy overlap, tape over edges",
  "rotation_habit": "slight tilts ±8°",
  "text_style": "short handwritten captions, dates in corners",
  "recurring_elements": ["washi tape", "stamps", "pressed flowers"]
}
```

The Style Profile is shown to the user (editable chips), and they can toggle it on as an extra input to the Theme Blend Agent ("Match my style").

## 5. Architecture

```
┌──────────────────────── Flutter (Android) ────────────────────────┐
│ Capture · Review · Archive · Library/Book · Canvas · Agent UI     │
│ State: Riverpod   Storage: JSON index + PNG files (app docs dir)  │
└──────────────▲───────────────────────────────────────┬────────────┘
               │ HTTPS (JSON + multipart), SSE for agent progress
┌──────────────┴───────────────────────────────────────▼────────────┐
│                    FastAPI proxy (Python 3.12)                     │
│  /segment  /enrich  /prompts  /agent/plan  /agent/build  /import   │
│  Provider adapters ── SegmentationProvider (SAM 3.1)               │
│                    ── VisionLLMProvider   (Muse Spark)             │
│                    ── AgentLLMProvider    (Muse Wonder)            │
│                    ── ImageGenProvider    (Muse Image)             │
│  Image utils: Pillow/numpy (crop, feather alpha, k-means palette)  │
└──────────────────────────────┬─────────────────────────────────────┘
                               ▼
                 Hackathon-hosted Meta model APIs
```

**Key decisions**
- **The proxy holds all API keys.** The app never sees them; they're loaded from env vars and validated at startup.
- **Provider adapters** wrap each Meta API behind an interface, so a mock provider (fixtures) lets the app be built and demoed offline, and endpoint changes stay contained.
- **The proxy is stateless with respect to user data.** The archive lives on the device. For agent calls, the app sends the relevant scrap summaries (IDs, tags, OCR text, palette, thumbnail URL or base64), so `search_archive` runs over the payload the client sends. P3 cloud sync would move this server-side.
- **Images:** full-res scraps stay on the device; the proxy gets downscaled copies (max 1536 px) for analysis.

### 5.1 Meta Model API (as researched 2026-10-29; confirm on Day 1)

- **Endpoint:** `https://api.meta.ai/v1`, reported to be OpenAI-compatible (Chat Completions). The proxy can use the standard `openai` Python SDK with `base_url` pointed there, so no custom HTTP client is needed.
- **Agent model:** `muse-wonder-1.0`. Not `muse-wonder-full-1.0`, which is only available in a Muse Code subscription and has no API.
- **Tool calling is native** (`tools`, `tool_choice`, parallel tool calls), and so are structured output (`response_format` with a JSON schema) and streaming (`stream: true`).
- **Agent loop:** send theme + tool schemas → model returns `tool_calls` → proxy runs `search_archive` / `generate_ephemera` → results go back as `tool` messages → repeat until the model returns the Blend Plan. The final layout step uses structured output, not a tool.
- **Reasoning effort** is tunable (minimal → max). Use low/medium for planning to keep latency under the 20 s target.
- **Budget:** $150 API credits per team. Reported pricing is about $4 / $20 per 1M input/output tokens. Reported limits are 3,000 requests and 4M tokens per minute.
- **Muse Image pricing:** a flat **$0.01 per image returned**, the same at any `reasoning_strength` and with or without tool use. A request for `n` images costs `n` × $0.01. Images that fail or are removed by safety filtering aren't billed. Image generation is therefore not a budget concern (1,000 images = $10); Muse Wonder tokens are the main cost.
- **Budget estimate (rough, at $4 / $20 per 1M tokens):**

  | Call | Assumed tokens | Est. cost | Calls on $150 |
  |---|---|---|---|
  | Agent plan (~5 tool turns, 20-scrap archive resent each turn) | ~30k in / 3k out | ~$0.18 | ~800 |
  | Agent build (layout step) | ~8k in / 1k out | ~$0.05 | ~3,000 |
  | Enrichment per scrap (Muse Spark, if priced like Wonder) | ~2k in / 300 out | ~$0.015 | ~10,000 |
  | Generated image | n/a | $0.01 | 15,000 |

  A heavy week (100 full agent runs + 300 scraps enriched + 200 images) comes to about **$30**, well within $150.
- **Cost controls:** develop against mock providers (real calls only behind an env flag); send scrap summaries, not images, to the agent; use low/medium reasoning effort; use prompt caching for the system prompt + tool schemas if the endpoint supports it; cache demo responses; log tokens per request.
- **Not planned:** self-hosting or fine-tuning. Muse models are API-only, and switching the core AI away from Meta's models would weaken the hackathon pitch.
- The model is listed as a preview, so the hackathon deployment may differ from the public docs.

### 5.2 API Contract (sketch)

| Method & path | Request | Response |
|---|---|---|
| `POST /segment/auto` | multipart `image` | `{image_id, width, height, photo_jpeg, masks: [{id, bbox, score, preview_png}]}`. `photo_jpeg` is the upright, downscaled photo the masks refer to; `preview_png` is a white mask cropped to `bbox`, tinted in the app |
| `POST /segment/point` | `image_id`, `points: [{x,y,label}]` | `{mask: {...}}` |
| `POST /cutout` | `image_id`, `mask_ids`, `cut_style: tight\|sticker\|margin`, `cut_size: s\|m\|l` | `{scraps: [{png_base64, bbox}]}` |
| `POST /enrich` | `scrap_png` | enrichment JSON (4.3) |
| `POST /prompts` | `scrap_summaries[]` | `{prompts: [str], captions: [str]}` |
| `POST /agent/plan` | `{theme, pinned_ids, archive: [ScrapSummary], style_profile?}` | SSE: progress events, then `BlendPlan` |
| `POST /agent/build` | `{plan, archive}` | SSE: progress events, then `{generated_scraps[], layout[]}` |
| `POST /import/style` | `page_images[]` | `StyleProfile` |

All responses use one envelope: `{ok: bool, data: T | null, error: {code, message} | null}`.

### 5.3 Data Model (on device)

```
Journal   { id, title, cover_style, created_at, page_ids[] }
Page      { id, journal_id, kind: editable|scanned, paper, elements[], thumbnail_path, updated_at }
Element   { id, kind: scrap|text|stroke, scrap_id?, text?, font?, points?, color?,
            x, y, scale, rotation, z }          // normalized 0..1 page coords
Scrap     { id, png_path, width, height, source: capture|imported|generated,
            capture_id?, type, tags[], ocr_text, entities, mood[], palette[],
            description, enriched: bool, created_at }
Capture   { id, photo_path, created_at, scrap_ids[] }
StyleProfile { id, journal_ids[], themes[], palette[], density, layering,
               rotation_habit, text_style, recurring_elements[] }
```

Page state is immutable: every edit produces a new `Page` value, which keeps undo/redo simple.

## 6. Non-Functional Requirements

- **Performance:** canvas runs at 60 fps with 30 elements; page flip at 60 fps; extraction round-trip under 6 s for auto masks.
- **Offline:** the Archive, Library and Canvas fully work offline. AI features show a clear "needs connection" state.
- **Resilience:** every AI call has a timeout, a retry for transient errors, and a user-visible error with a retry button. A failed enrichment leaves the scrap usable (`enriched=false`) and it retries later.
- **Privacy:** photos are only sent for processing; the proxy doesn't persist images beyond the request (temp files are deleted). This is stated in the app's About screen.
- **Security:** keys stay server-side; uploads are validated (type and size ≤ 10 MB); the proxy has basic rate limiting; CORS is locked down.
- **Quality (scaled to 7 days):** unit tests where bugs would hurt the demo most: the proxy endpoints (adapters mocked), mask → cutout conversion, agent output validation, and the Dart page-state/undo logic. Plus one integration test of the hero flow against mock providers. No blanket coverage target during the hackathon.

## 7. Demo Script (≈3 min)

1. **Hook (15 s):** a messy desk of tickets, a café receipt, pressed flowers and washi tape. "Digitizing this used to take an hour."
2. **Snap → Cutout (40 s):** take the photo, SAM 3.1 auto-detects every item, tap to add the one it missed, save. Zoom in on a deckle edge and the translucent tape.
3. **Archive + OCR (20 s):** the receipt shows its date, place and tags; a journal prompt is suggested.
4. **Theme Blend Agent (60 s):** type "slow Sunday café morning, warm browns" and pin the receipt. Show the streamed plan with chosen scraps, a palette and (if P2 shipped) two generated stamps. Remove one scrap, approve, and the page builds itself.
5. **Edit + Book (30 s):** nudge a scrap, add a handwritten caption, doodle, close the page, and flip through the book.
6. **(Stretch bonus, 15 s, only if it shipped):** import a photo of an old physical journal page and show the extracted Style Profile and "Match my style."
7. **Close (10 s):** Meta models used, and what's next (aging effects, cloud sync).

## 8. Milestones (7-day plan)

Solo build: features are built **vertically** (app screen + its proxy endpoint together), so each day ends with something that works on the phone. Day 1 = 2026-10-29.

| Day | Build | End-of-day check |
|---|---|---|
| **1** | Scaffold the Flutter app + FastAPI proxy, response envelope, mock providers. **Confirm the hackathon key serves `muse-wonder-1.0` with one test tool call, plus SAM edge format and quotas.** Capture screen | App takes a photo and gets mock masks back from the proxy |
| **2** | Real SAM 3.1 adapter (auto + tap), mask review screen, cut styles, save to the Archive | Real cutouts of real scraps in the Archive |
| **3** | Canvas editor (transforms, layers, text, undo/redo, PNG export) + library and book flip (package) | **Cut-line check:** the full hero flow works on the device |
| **4** | Enrichment (OCR + tags + palette) + agent plan with `search_archive`, SSE progress, plan cards UI | A theme prompt returns an approvable plan |
| **5** | Agent build (layout step + validation). If on track: `generate_ephemera`, freehand, prompts (P2). **Feature freeze tonight** | Agent builds a page end-to-end; demo assets cached |
| **6** | **Demo video day:** script (section 7), record, edit. Fix only bugs that show up on camera. README with setup steps and a list of the Meta models used | Final video exported |
| **7** | **Submission & social:** submit the repo + video, post on social media (cut a 30–60 s vertical clip from the video) | Submitted |

**Daily rule:** commit at the end of each day with the hero flow still working, so there's always a demoable build.

## 9. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Hosted API quotas or latency during the demo | Cache results for demo assets; mock provider fallback; pre-record the agent segment as a backup |
| SAM over- or under-segments cluttered photos | Capture hint (contrasting background), area filter, tap refine |
| Agent produces off-theme or overlapping layouts | Structured output with schema validation; the app clamps the layout; user approval step |
| Generated ephemera looks too clean next to real scraps | Prompt for "scanned, paper texture, slight imperfection"; run it through the same cutout pipeline |
| Scope creep, solo with 5 build days | Day 3 cut-line check (section 3); P2/Stretch start only after the agent builds pages end-to-end |
| API access confirmed late | Check on Day 1; mock providers let the app keep moving regardless |
| Burning the $150 credits during development | Build against mock providers by default; real calls only behind an env flag; log token usage per request; cache demo responses |
| Page-flip build time | Use an existing page-curl package; flip thumbnails, not live canvases |
| Video squeezed by late features | Feature freeze on the night of Day 5; Day 6 is video only |

## 10. Open Questions

- **SAM cutout edges:** does SAM 3.1 give each pixel a yes/no "inside the object" answer (hard edges), or a 0–100% value (soft edges)? Soft edges let washi tape stay semi-see-through. With hard edges, the proxy fakes it by feathering the border. (The cut styles in 4.1 work either way.)
- ~~**Muse Wonder and tools:** native tool calling or a JSON fallback?~~ **Resolved:** native tool calling is supported (see 5.1), so no JSON fallback is needed. Still to do: one live test call with the hackathon key on Day 1.
- ~~Muse Image pricing?~~ **Resolved:** $0.01 per returned image (see 5.1).
- Muse Spark model ID and whether it shares the same endpoint and credits.
- Whether the Style Profile should also bias manual editing (e.g. a "tilt like me" auto-rotation) or only the agent.
