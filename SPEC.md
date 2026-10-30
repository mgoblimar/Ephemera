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
| **P1** | **UI/UX polish pass** (4.8) | The demo video is judged on looks: style, motion, empty states, app icon |
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
2. The app uploads the image to the proxy, which auto-detects the items. SAM 3.1 has no "segment everything" mode, so the proxy detects in two steps:
   - **Plan A (default):** Muse Spark looks at the photo and returns a box and a type label (ticket, receipt, botanical, tape, …) for each item. All boxes, up to 16, then go to SAM 3.1 as box prompts in **one** request. This gives masks plus labels for about $0.007 per photo.
   - **Plan B (fallback if Spark's boxes are poor):** send several concept prompts (`"ticket"`, `"receipt"`, `"flower"`, `"washi tape"`, `"sticker"`, `"paper"`) to SAM in parallel, then merge overlapping masks. About $0.015 per photo.
   - **Decided on Day 2: Plan A.** It was tested live on 3 real photos (5 mixed scraps; a printed box; a white paper bag on a white surface):

     | | Plan A | Plan B |
     |---|---|---|
     | 5 mixed scraps | all 5, plus a box edge at the photo's border | all 5 |
     | Printed box | found | **missed**: no matching word |
     | White bag on white | one clean cutout | bag, **plus 2 printed logos** wrongly cut out |
     | Cost per photo | ~$0.003 | ~$0.02 |
     | Time per photo | ~10 s (Spark ~6 s, SAM ~4 s, decode ~1 s) | ~3–6 s (8 requests in parallel) |

     Plan B only finds what's on its word list, and junk-journal scraps can be anything. Plan B stays available as `AUTO_DETECT_STRATEGY=concepts`.
   - Cutout quality from SAM is excellent: torn and zig-zag edges are followed precisely, and low contrast (white on white) is no problem.
   - Speed-ups still to try for Plan A: send Spark a smaller image (~768 px); try `reasoning_effort="none"`. Spark uses ~260 reasoning tokens at `minimal`, and ~450–980 at `low`.
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

#### 4.1a Scan session (built Day 2; replaces steps 2–5 as the main flow)

Cutting costs ₱0.16 per SAM request (pesos at ₱64/USD), so the flow splits finding pieces from cutting them:

1. **Scan:** add any number of photos. Each goes only to Muse Spark detection (`/scan/detect`, ~₱0.01). Pieces show as thumbnail tiles, all ticked by default.
2. **Choose:** untick pieces not worth keeping. The cost line shows `N chosen · R cut requests · ≈₱X`.
3. **Cut once:** `/scan/cut` crops each chosen piece from its full-size photo, packs up to 16 onto a **contact sheet** and sends it to SAM as **one** request. Masks are mapped back and cut at full resolution, and saved grouped per photo.

Measured: 14 pieces from 3 photos = 1 billed image (`images_processed=1`), same quality as cutting per photo. Five photos with 12 kept pieces cost ~₱0.22, versus ~₱0.96 with one SAM call per photo.

The Day 1 review screen (tap-to-add, refine) is kept in the code but not reachable. Refinement is parked (see 4.1c).

#### 4.1b Split into design elements (built Day 2; quality in backlog)

A scrap often holds smaller designs worth cutting out on their own: the SUMO lettering on a wrapper, the oval logo on a paper bag, a character on a box. Sometimes the whole item is wanted, sometimes just a piece of it, sometimes both.

- A **Split** button on each piece tile sends a close-up crop of that piece to Muse Spark (`detect_elements`, ~₱0.01). Spark returns elements labelled `logo · lettering · illustration · badge · character · pattern · photo`.
- Elements appear as extra tiles under their parent. Any mix of whole items and elements is cut in the same batched request (16 per SAM call). Default cut style for elements: **Sticker**.
- Live test (Day 2): Jamaican bag logo and pattie came out as clean die-cut stickers. Sumo lettering, badge and cookies were good after **speck removal** (`drop_islands` keeps parts ≥15% of the largest). The cream box missed its hero jar illustration, so the prompt needs "include the main illustration even if large".

**Status (Day 2 evening): built, quality not good enough yet; moved to the backlog.** Tested live on 3 wrappers (15 elements, 2 SAM requests):
- Good: logos and lettering with their own outline. The SUMO logo is clean after speck removal.
- Poor: Spark's boxes are loose or overlap neighbours (a badge swallowed an adjacent cookie and background). Shapes printed on busy backgrounds (a milk splash) give vague regions.

**Backlog ideas to improve it:**
1. Ask Spark for tighter boxes and only "clear, self-contained" elements, and drop overlapping or huge boxes server-side.
2. Run SAM per element with negative points on neighbouring elements, so they don't merge.
3. Refinement taps (4.1c) for manual fixes.
4. Edge snapping.
5. Consider Muse Spark at higher reasoning effort (not contributor) for element boxes only.

#### 4.1c Parked: refinement

These are batched too, with all pending edits in one SAM request:
- Add/erase taps and drag-a-box on a piece.
- Duplicate a piece to make variants (figure only vs figure + board).
- A "Find…" word search (SAM concept prompt, 1 word per request).
- Edge snapping.

**Acceptance criteria**
- A photo with 3–6 items yields at least one usable cutout per item without manual tapping in most cases.
- Translucent washi tape keeps partial alpha, not a hard 0/1 mask (where SAM's output allows it).
- Tap-to-add returns a mask in under 3 s on demo Wi-Fi.
- Masks smaller than 1% of the image area are filtered out as noise.

### 4.2 Scrap Archive (P0)

A grid of every scrap ("scrapbook wall" in 4.8), with **filters that combine**: each filter narrows the result, and active filters show as removable chips.

| Filter | Source of the data | Status |
|---|---|---|
| **Search text** (words on the scrap, description) | `ocr_text`, `description` (enrichment) | Data ready |
| **Vibe / mood** (cozy, nostalgic, playful…) | `mood` (enrichment) | Data ready |
| **Tags** (coffee, yellow, travel…) | `tags` (enrichment) | Data ready |
| **Type** (ticket, wrapper, sticker, logo, lettering…) | `type` (detector / Split / enrichment) | Data ready |
| **Colour** (tap a swatch) | `palette` | Data ready |
| **Split from** (e.g. "elements of the Sumo wrapper") | **new:** `split_from`: parent piece's label + capture, set when a Split element is cut | Needs a small data change |
| **Date added** (today, this week, a date range) | `created_at` | Data ready |
| **Availability** (unused / already used in a physical spread) | **new (next iteration):** `physical_status` + `used_in` note | Planned |

**Next iteration: "physically used" tracking.** Journalers glue real scraps into real spreads, and then those scraps aren't available anymore.
- Each scrap gets a status: `available` · `used` (glued into a physical spread) · optionally `reserved` (set aside for a planned spread). There's an optional note or link to which spread.
- Archive filter **"Available only"** is on by default when planning.
- The Theme Blend agent skips `used` scraps unless asked ("include used ones for a digital-only page").
- Marking is quick: long-press → "Mark as used", or multi-select → mark several.
- This tracks the *physical* scrap. The *digital* cutout can still be reused on digital pages.

**Other archive features:**
- Scrap detail view: image, OCR text, tags (editable), palette swatches, source photo, split-from parent.
- Long-press to multi-select, then "Add to page" or "Blend with agent" (pinned scraps).

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
- At most 8 tool calls per plan, counting each parallel call separately (token cost and latency) and at most 4 generations per build (latency; images cost only $0.01 each). Each `generate_ephemera` call may request `n=2` variants so the user can pick one in the plan cards.
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

### 4.8 UI/UX polish (P1, added Day 3)

The features work, but the app still looks like stock Material. The demo video needs it to feel like a **tactile scrapbook studio**, not a settings screen.

**Direction (confirmed):** a **junk-journal desk** feel. Default theme: **Warm editorial scrapbook**.
- Paper textures everywhere (not flat cream), torn-paper and washi-tape accents.
- A serif display font for headings, paired with the handwriting fonts already in the editor.
- Scraps shown as physical objects: soft drop shadows and slight tilts.
- Terracotta and moss colours carry meaning (selected / action), not just decoration.

**Themes:** the look is a swappable token set (Flutter `ThemeExtension`): colours, display and body fonts, paper texture, decorations (tape, stickers), shadow and tilt. Screens read tokens, never hard-coded colours, so a theme switch restyles the whole app.

| Theme | Feel | Hackathon scope |
|---|---|---|
| **Desk** (default) | Warm editorial scrapbook: kraft and cream paper, serif + handwriting, washi tape, terracotta and moss | Build fully (A list below) |
| **Cozy cat** | Cute and playful, inspired by the mofusand mood: pastels, rounded shapes, original cat-ear and paw doodles, bouncy motion. **Original art only; no mofusand characters, artwork or name** (copyrighted brand). | Second theme if Day 5 allows; else post-hackathon |
| **Studio** | Clean modern: white, bold type, scraps as the only colour | Post-hackathon |
| **Vintage** | Moody kraft and ink, aged paper, stamps, typewriter type | Post-hackathon |

A theme picker lives in a small settings sheet (palette icon on the Journals tab). The choice is saved on the device.

**Must-have for the video (A):**
1. **Theme system + Desk tokens first:** display + body fonts, colour roles, paper texture, shadows, spacing, all as a `ThemeExtension`, so the Day 4–5 screens are built in the style and other themes can be added later.
2. **Archive** as a scrapbook wall: masonry layout, tilted scraps with shadows, and the **combined filters from 4.2** (search, vibe, tags, type, colour, split-from, date).
3. **Journal shelf:** textured cloth/kraft covers with a spine and title label.
4. **Editor:** corner handles for scale and rotate (instead of a plain border), a tool bar styled like a strip of washi tape, light haptics on select and drop.
5. **Scan session:** a nicer "finding pieces…" state (shimmer over the photo), and a short cut-out reveal animation when scraps come back.
6. **App icon, name and splash screen** ("EphemeraAI"), and friendly empty states with a small illustration.

**Nice-to-have (B):**
- A real page-curl turn in the book.
- A hero transition from scrap to canvas.
- Onboarding with 3 cards.
- Sound or haptic touches.

**Rules:** no new features in this pass; check every screen at tablet and phone width; keep tap targets ≥48 px; respect reduced motion.

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

### 5.1 Meta Model API (from dev.meta.ai docs, read 2026-10-29)

**Endpoints and auth**
- OpenAI-compatible base: `https://api.meta.ai/v1`, with Chat Completions (`/v1/chat/completions`) and Responses (`/v1/responses`). An Anthropic-compatible Messages API is at `https://api.meta.ai`.
- Auth: `Authorization: Bearer <key>`. The docs name the env var `MODEL_API_KEY`; the proxy accepts `MODEL_API_KEY` or `META_API_KEY`.
- The proxy uses the standard `openai` Python SDK with `base_url` set, plus `meta-sam-parser` for SAM output.

**Models**

| Use in EphemeraAI | Model ID | Price | Rate limit (per team) |
|---|---|---|---|
| Theme Blend Agent | `muse-wonder-1.0` | $4.00 in / $0.20 cached in / $20.00 out per 1M tokens | 3,000 RPM, 4M TPM |
| Enrichment (OCR, tags), object detection, prompts | `muse-spark-1.3` | $1.25 in / $0.15 cached in / $4.25 out per 1M tokens | 3,000 RPM, 4M TPM |
| Generated ephemera | `muse-image-1.0` | $0.01 per returned image (failed or safety-filtered images aren't billed) | 150 RPM |
| Cutouts | `sam-3.1` | $2.50 per 1,000 images ($0.0025 per request) | 3,000 RPM |

- Context window is 1,048,576 tokens and the output limit is 131,072 tokens, for both Muse text models.
- Don't use `muse-spark-*-contributor`: it's cheaper, but Meta may train on your content.

**Which model does what**

Each job has its own setting in `proxy/.env`, so models can be swapped without code changes.

| App feature (spec section) | Model | Setting | Testing profile | When it runs |
|---|---|---|---|---|
| Auto-detect items in a photo, step 1: boxes + type labels (4.1) | Muse Spark 1.3 (vision) | `VISION_MODEL` | contributor | Once per captured photo |
| Auto-detect, step 2: cut out every detected item (4.1) | SAM 3.1, box prompts | `SAM_MODEL` | standard | Once per photo (up to 16 items) |
| Tap to add a missed item / refine a cutout (4.1) | SAM 3.1, point prompts | `SAM_MODEL` | standard | Each tap |
| OCR, tags, mood, description for each scrap (4.3) | Muse Spark 1.3 (vision) | `VISION_MODEL` | contributor | Once per saved scrap, in the background |
| Journal prompts & captions (4.3) | Muse Spark 1.3 (text) | `VISION_MODEL` | contributor | On request |
| Theme Blend Agent: plan, calls `search_archive` / `generate_ephemera` (4.6) | Muse Wonder 1.0 | `AGENT_MODEL` | contributor (Spark) | Each "Plan" tap |
| Theme Blend Agent: layout placements, structured output (4.6) | Muse Wonder 1.0 | `AGENT_MODEL` | contributor (Spark) | Each "Build" tap |
| `generate_ephemera`: stamps, tape, labels (4.6) | Muse Image 1.0 | `IMAGE_MODEL` | standard | Up to 4 per build |
| Cut out generated ephemera (4.6) | SAM 3.1, concept prompt (e.g. `"stamp"`) | `SAM_MODEL` | standard | Once per generated image |
| Style Profile from imported journal pages (4.7, stretch) | Muse Spark 1.3 (vision, multi-image) | `VISION_MODEL` | contributor | Once per import |

No model is used for:
- cut styles (tight, sticker, margin)
- palettes (local k-means)
- `search_archive` itself (runs in the proxy over the scrap summaries the app sends)
- the canvas, the book and archive filters

**Profiles**
- **Testing:** `AGENT_MODEL` and `VISION_MODEL` set to `muse-spark-1.3-contributor`, about 70× cheaper than Muse Wonder. Meta may train on what's sent, so use only test photos you're fine sharing. Also check on the first real call that contributor mode accepts images.
- **Demo / real users:** `AGENT_MODEL=muse-wonder-1.0` and `VISION_MODEL=muse-spark-1.3`. These keep the privacy promise in section 6, and the pitch is "built on Muse Wonder".
- SAM and Muse Image have no contributor mode and are already cheap.
- Before recording the video, re-test the agent on Muse Wonder: prompts tuned on Spark may behave differently.

**Agent loop (Muse Wonder)**
- Tool calling is native on all three APIs. **Use the Responses API for the agent**, because it carries the model's reasoning across tool-call turns (`include: ["reasoning.encrypted_content"]`, or `previous_response_id`). The docs warn that Chat Completions drops reasoning between turns, which can make long tool loops erratic.
- Loop: send theme + tool schemas → model returns tool calls → proxy runs `search_archive` / `generate_ephemera` → results go back → repeat until the model returns the Blend Plan. The final layout step uses structured output, not a tool.
- Reasoning effort ranges from `none` to `max`. Use `low`/`medium` for planning to stay under the 20 s target.
- **Measured on Day 1 (default effort, 4 live runs):**
  - The model usually makes **3–4 `search_archive` calls in parallel** in one turn, using different phrasings of the theme. **Every tool call must get its own tool response, or the next request fails with HTTP 400.** The proxy should also merge and dedupe results across those calls.
  - Latency was 3–5 s for the first turn and 6–15 s for the turn after the tool results, so about 10–20 s per plan. That's on target, with no room to spare.
  - Prompt caching works automatically: 500 of 567 prompt tokens were served from cache on repeat calls.
  - Each check run cost about **$0.01–0.03**, not "under $0.01" as first estimated. **Reasoning tokens are billed as output ($20/1M)**, and they were 40–85% of each run's output (80–978 per turn). Five runs used about $0.07–0.13.
  - Budget rule: a Muse Wonder call costs roughly **$0.02 per turn**, so a 2-turn plan is about $0.05. Develop the agent against `muse-spark-1.3` (output is ~5× cheaper) or mocks, and switch to Muse Wonder only for final tests and the demo.
- Not needed for this app: the docs' coding-agent, agent-framework (Claude Agent SDK, Codex app-server) and computer-use guides. Those drive a terminal or a screen; our agent only calls two of our own functions.

**SAM 3.1: how it actually works**
- Called through `POST /v1/responses` with `model: "sam-3.1"`. The photo goes in an `input_image` part (a public URL or a base64 data URL), and the prompt goes in an `input_text` part.
- **Prompt types:**
  - *Concept:* one short noun phrase, such as `"ticket"`. Returns every matching instance.
  - *Point/box:* special tokens, e.g. `<0f>1<|point;x=..;y=..;w=..;h=..|>`, with a leading `-` for a negative point. Up to **16 objects per request**. Build these with `meta_sam_parser.build_object_prompt`, not by hand.
- **There is no "segment everything" mode.** See the auto-detect plan in 4.1.
- **Output:** streamed text lines. Each object is a box (`x1,y1,x2,y2` in source pixels) followed by a mask encoded as `data=<H>,<W>,<marker><base85 payload>`.
  - **Masks are binary (0/1)**, and the mask raster is **smaller than the photo**, so the proxy upsamples it to photo size before feathering.
  - Decode with `meta_sam_parser.decode_mask_to_raster` (`pip install meta-sam-parser`, version ≥ 0.1.0; pure Python, no dependencies).
  - `metadata.include_confidence: "true"` (a string, not a boolean) adds a `c` score from 0 to 1. Zero matches is a normal, empty response.
- Errors: a `400` is permanent (fix the input; don't retry); `404 model_not_found` means a wrong model ID or no access.
- Not documented: image size limits and latency. Measure both on Day 2.

**Budget estimate (at published prices)**

| Call | Assumed size | Est. cost | Calls on $150 |
|---|---|---|---|
| Agent plan (Muse Wonder, ~5 tool turns) | ~30k in / 3k out | ~$0.18 | ~800 |
| Agent build (layout step, Muse Wonder) | ~8k in / 1k out | ~$0.05 | ~3,000 |
| Enrichment per scrap (Muse Spark) | ~2k in / 300 out | ~$0.004 | ~37,000 |
| Auto-detect a photo (Muse Spark boxes + one SAM request) | ~2k in / 500 out + 1 image | ~$0.007 | ~21,000 |
| Tap-to-add (one SAM request) | 1 image | $0.0025 | 60,000 |
| Generated image (Muse Image) | n/a | $0.01 | 15,000 |

A heavy week of 100 agent runs, 150 photos, 300 taps, 300 enrichments and 200 images comes to about **$28**. Muse Wonder is ~80% of that.

- **Cost controls:** develop against mock providers (real calls only behind an env flag); send scrap summaries, not images, to the agent; use low/medium reasoning effort; cached input is 20× cheaper, so keep the system prompt + tool schemas identical across calls; cache demo responses; log tokens per request.
- **Not planned:** self-hosting or fine-tuning. Muse Wonder is API-only (an open-weight "Muse Spark Open" exists but isn't needed), and switching the core AI away from Meta's hosted models would weaken the hackathon pitch.
- Confirm on Day 1 that the hackathon key can reach all four model IDs.

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
| **1** ✅ | Done: Flutter app + FastAPI proxy with mocks; capture, mask review, tap-to-add, cut styles, save to the Archive (pulled forward from Day 2); Muse Wonder tool calling confirmed with the real key; SAM/pricing docs read | ✅ Mock hero flow works end to end; 25 proxy + 14 app tests pass |
| **2** ✅ | Done: real SAM 3.1 + Muse Spark (Plan A chosen); sticker sheets split per sticker; full-resolution cutouts, hole filling, speck removal, scrap types; **scan session with contact-sheet batching** (16 pieces per ₱0.16 request); element detection proven live | ✅ Real cutouts on the tablet; 62 proxy + 19 app tests pass |
| **3** ✅ | Done: canvas editor (drag/pinch/rotate, layers, handwriting text, paper styles, undo/redo, autosave, PNG export) + journal library + book with 3D page turn; Split built (quality in backlog) | ✅ **Cut line passed on the tablet** (Oct 30): scan → cut → collage → page flips; 65 proxy + 34 app tests |
| **4** ✅ | Done: theme system (Desk tokens); real Muse Spark enrichment in the background (50/50 scraps, 0 failures); Theme Blend plan step (Responses API, `search_archive`, plan cards, Build page with a simple cascade); split-from data | ✅ Live on the tablet (Oct 30): a theme gave a 6-scrap plan in ~19 s with 4 searches; page built. Simple cascade overlaps scraps, so the agent layout is Day 5 |
| **5** | **Morning:** agent build (layout step + validation). **Afternoon:** UI/UX polish pass (4.8 A2–A6) including **archive filters (4.2)**, then the Cozy cat theme if time. P2 (`generate_ephemera`, freehand, prompts) only if both are done. **Feature freeze tonight** | Agent builds a page end-to-end; every demo screen polished; demo assets cached |
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

- ~~**SAM cutout edges:** hard or soft?~~ **Resolved:** binary (hard) masks at a lower resolution than the photo. The proxy upsamples and feathers them. Washi tape won't keep real translucency in the MVP.
- ~~**Auto-detect:** Plan A or Plan B?~~ **Resolved:** Plan A (see 4.1 for the test results).
- ~~Does contributor mode accept images?~~ **Resolved:** yes. `muse-spark-1.3-contributor` handled all three photos.
- SAM latency: **resolved**, 1.5–3.7 s per request at 1536 px. SAM's image size limit is still undocumented; 1536 px works.
- ~~**Muse Wonder and tools:** native tool calling or a JSON fallback?~~ **Resolved:** native tool calling is supported (see 5.1), so no JSON fallback is needed. Still to do: one live test call with the hackathon key on Day 1.
- ~~Muse Image pricing?~~ **Resolved:** $0.01 per returned image (see 5.1).
- ~~Muse Spark model ID?~~ **Resolved:** `muse-spark-1.3`, same endpoint and key (see 5.1).
- Whether the Style Profile should also bias manual editing (e.g. a "tilt like me" auto-rotation) or only the agent.
