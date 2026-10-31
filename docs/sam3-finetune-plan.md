# Plan: fine-tune SAM 3 to find scraps

Status: **parked (post-hackathon)**. Collecting the dataset and preparing the cut-outs is more work than fits before the Nov 2 feature freeze. Summary in [SPEC.md 8.1](../SPEC.md).

## The idea

Today a scan is two steps: Muse Spark draws a box around each scrap, then SAM 3.1 cuts out what's inside the box. Most bad cuts come from Spark's boxes, which vary run to run, sit a little low and run into shadows.

**SAM 3** is the open-weight member of the same Meta family. It can find *every* instance of a concept from a short text prompt. Fine-tuned on the phrase "journal scrap" with photos like ours, one call would find and cut every piece, with no Spark boxes in between. Spark would keep labelling and enrichment.

Check first: SAM 3's weights are open (`facebook/sam3`, gated). It isn't confirmed that SAM 3.1's weights are. If they aren't, tune SAM 3.

## Steps

### 1. Logins (user, ~15 min, free)
- **Hugging Face:** accept the licence on `facebook/sam3` (approval can take hours, so do this first), then create a *read* token.
- **Modal:** `pip install modal`, then `modal setup` (browser login).
- The user stores the Hugging Face token as a Modal secret. It's never pasted into chat or the repo.

### 2. Ingredients (mostly user, ~30 min)
- **Cut-outs:** clean transparent PNGs from the app archive, pulled with adb. 50+ is good, more and more varied is better.
- **Empty backgrounds:** ~20 photos of surfaces we really scan on (mat, desk, table, bed) in different light. The model learns what is *not* a scrap from these.
- **Exam photos:** the real scans in `proxy/test_photos/eval`. Never used for training.

### 3. Synthetic practice photos (~2 h, free, on the laptop)
- A script pastes cut-outs onto backgrounds at random positions, sizes and angles, with overlaps, soft shadows and lighting changes.
- Every pasted piece's outline is known exactly, so there's no hand-labelling.
- Target ~5,000 images, written in the format SAM 3's training code expects (COCO-style masks + the phrase "journal scrap").

### 4. Train on Modal (~2–3 h per run, credits)
- One A100 is about ₱160 an hour, so a run costs ~₱300–500. Budget two runs, ~₱1,000.
- Fine-tune the detector head (or LoRA). Track box recall and mask IoU on the exam photos while training.

### 5. Exam (~1 h, cheap)
- Run `proxy/scripts/scan_eval.py` on the real photos: tuned SAM 3 vs today's Spark + SAM 3.1.
- Compare pieces found, shape score and rough cut-outs.
- **Adopt only if it clearly wins.** Otherwise it stays a roadmap item.

### 6. Plug it in (~2 h)
- Serve on a Modal (or Baseten) GPU endpoint: `/find_scraps` returns boxes + masks.
- Add `AUTO_DETECT_STRATEGY=sam3_tuned` beside Plan A, so one setting switches back.
- A GPU that isn't kept running takes 30–60 s to start on the first scan. Keep it warm only while recording (~₱100+ an hour).

### 7. Test on the tablet (user)

## Why it's parked

- Steps 2–3 are the real work: enough varied cut-outs, real backgrounds, and practice photos realistic enough to transfer to real scans.
- First training runs in a new setup almost always need a few tries.
- The demo works today with Spark boxes plus the y-bias fix and the stricter prompts.

## Cheaper path later: learn from real use

Log (opt-in) every scan's boxes plus what the user kept, unticked, removed or re-split. That's labelled data for free, collected while the app is used, and a better training set than synthetic photos.

Credits: Modal or Baseten for training and serving; Fireworks is better kept for hosted LLM work (e.g. a cheaper caption model).
