# LTX Desktop vs Wan2GP: Investigation Report

**Date:** 2026-03-10  
**Purpose:** Investigate whether LTX Desktop's workflow/settings can improve Wan2GP LTX2 generation quality.

---

## 1. LTX Desktop – Open Source Status

| Property | Value |
|----------|-------|
| **License** | Apache 2.0 |
| **Repository** | [Lightricks/LTX-Desktop](https://github.com/Lightricks/LTX-Desktop) |
| **Backend** | Python + FastAPI (`backend/`) |
| **Inference** | Custom pipeline using `ltx-core` and `ltx-pipelines` from [Lightricks/LTX-2](https://github.com/Lightricks/LTX-2) |

LTX Desktop uses the same underlying LTX packages as the official repo; it does **not** use ComfyUI.

---

## 2. Sigma Schedules – Already Aligned

| Source | Stage 1 (DISTILLED_SIGMA_VALUES) | Stage 2 (STAGE_2_DISTILLED_SIGMA_VALUES) |
|--------|-----------------------------------|-----------------------------------------|
| **Wan2GP** | `[1.0, 0.99375, 0.9875, 0.98125, 0.975, 0.909375, 0.725, 0.421875, 0.0]` | `[0.909375, 0.725, 0.421875, 0.0]` |
| **LTX Desktop** | Same (from `ltx_pipelines.utils.constants`) | Same |
| **Official LTX-2** | Same | Same |

**Conclusion:** Wan2GP already uses the same sigma schedule as LTX Desktop and the official LTX-2 distilled pipeline. No change needed.

> **Note:** LTX Desktop has a fallback `[1.0, 0.9, 0.7, 0.5, 0.3, 0.2, 0.1, 0.04, 0.0]` when `ltx_pipelines` is not importable. That fallback is different, but the normal path uses the same schedule as Wan2GP.

---

## 3. Image Conditioning – Same Approach

| Approach | Frame 0 | Frame > 0 | Used By |
|----------|---------|-----------|---------|
| **image_conditionings_by_replacing_latent** | `VideoConditionByLatentIndex` | `VideoConditionByLatentIndex` | Wan2GP, LTX Desktop I2V |
| **combined_image_conditionings** | `VideoConditionByLatentIndex` | `VideoConditionByKeyframeIndex` | Official LTX-2 DistilledPipeline |

Wan2GP and LTX Desktop both use `image_conditionings_by_replacing_latent` for I2V: all conditioning frames use latent replacement. The official distilled pipeline uses `combined_image_conditionings` (replace for frame 0, keyframe for later frames).

**Conclusion:** Wan2GP and LTX Desktop already match for I2V conditioning. No change needed.

---

## 4. Denoising Loop – Core Logic Matches

Both use:

- `EulerDiffusionStep` for the stepper
- `simple_denoising_func` (no CFG for distilled)
- `post_process_latent` with denoise mask and clean latent
- Same `denoise_audio_video` → `noise_video_state` / `noise_audio_state` flow

Wan2GP adds optional features:

- `mask_context` (mask injection)
- `self_refiner_handler` (self-refinement)
- `callback` (progress)
- `interrupt_check`
- `offload.set_step_no_for_lora`

These are additive and do not change the core diffusion logic.

---

## 5. CFG / Guidance

- **Distilled pipeline:** Both use `simple_denoising_func` with no CFG (distilled model does not use CFG).
- **LTX Desktop default guider params** (for non-distilled): `cfg_scale=3.0`, `rescale_scale=0.7`, etc.
- **Wan2GP** distilled path: `alt_guidance_scale=1.0` (no CFG).

---

## 6. Differences That Could Affect Quality

### 6.1 Image Preprocessing

| Aspect | Wan2GP | LTX-2 / LTX Desktop |
|--------|--------|--------------------|
| **Image loading** | `load_image_conditioning` with `resample` | `load_image_conditioning` with `crf` (H.264-style compression) |
| **CRF** | `DEFAULT_IMAGE_CRF = 33` | Same in constants |
| **Resize** | `resize_aspect_ratio_preserving` | `resize_aspect_ratio_preserving` |

Wan2GP supports a `resample` parameter; the official pipeline uses `crf`. Worth checking alignment and whether CRF is applied consistently.

### 6.2 Conditioning Strategy: Replace vs Combined

- **Replace:** All frames use `VideoConditionByLatentIndex` (replace latent).
- **Combined:** Frame 0 uses replace, frame > 0 uses `VideoConditionByKeyframeIndex` (append keyframe tokens).

For I2V with a single first-frame image, both behave the same. For multi-keyframe or later-frame conditioning, the behavior differs.

**Possible experiment:** Try `combined_image_conditionings` in Wan2GP when multiple keyframes are used, to see if it improves quality.

### 6.3 ComfyUI vs LTX Desktop (from Issue #424)

The [ComfyUI-LTXVideo Issue #424](https://github.com/Lightricks/ComfyUI-LTXVideo/issues/424) notes:

- ComfyUI uses `SplitSigmas()` to split steps into 3 chunks (without/with/without conditioning).
- LTX Desktop does not use that split.
- Wan2GP also does not use `SplitSigmas()`; it aligns with LTX Desktop behavior.

---

## 7. Actionable Recommendations

### 7.1 Low Effort

1. **Image preprocessing**  
   Confirm alignment between Wan2GP’s `load_image_conditioning` and the official pipeline’s CRF/resize behavior. Ensure `resample` is used consistently where intended.

2. **Sync with upstream LTX-2**  
   Periodically compare Wan2GP’s vendored `ltx_core` and `ltx_pipelines` with [Lightricks/LTX-2](https://github.com/Lightricks/LTX-2) for bug fixes and minor improvements.

### 7.2 Medium Effort (Optional Experiments)

1. **Conditioning strategy**  
   Add an option to use `combined_image_conditionings` (replace for frame 0, keyframe for frame > 0) instead of `image_conditionings_by_replacing_latent` for multi-keyframe I2V scenarios.

2. **Alternative sigma schedule**  
   If LTX Desktop’s fallback schedule `[1.0, 0.9, 0.7, 0.5, 0.3, 0.2, 0.1, 0.04, 0.0]` is ever validated as better, expose it as an optional schedule.

### 7.3 Quality Debugging

If quality still differs from LTX Desktop:

1. **Reproduce in LTX Desktop**  
   Same prompt, seed, resolution, conditioning image, and model.

2. **Compare intermediate outputs**  
   Log latent states, denoise masks, and conditioning latents at each step for both pipelines.

3. **Check model loading**  
   Ensure same checkpoint, LoRA weights, and quantization (e.g. FP8).

4. **Text encoding**  
   Confirm Gemma text encoder output matches between Wan2GP and LTX Desktop (same prompt, same encoding path).

---

## 8. Summary

| Component | Wan2GP vs LTX Desktop | Status |
|-----------|----------------------|--------|
| Sigma schedule | Identical | No change |
| Stage 2 sigma | Identical | No change |
| I2V conditioning | Same (replace latent) | No change |
| Denoising loop | Same core logic | No change |
| CFG (distilled) | Both disabled | No change |
| Image preprocessing | Minor differences | Worth checking |
| Conditioning strategy | Replace vs combined | Optional experiment |

**Conclusion:** Wan2GP’s LTX2 distilled pipeline is already aligned with LTX Desktop and the official LTX-2 distilled pipeline. The sigma schedule and I2V conditioning behavior match. Any remaining quality differences are more likely from image preprocessing, model loading, or text encoding than from the diffusion workflow itself.

---

## 9. Files Referenced

- **LTX Desktop:** `/tmp/ltx-desktop-investigate/backend/services/ltx_pipeline_common.py`
- **LTX-2 ltx_pipelines:** `/tmp/ltx2-investigate/packages/ltx-pipelines/src/ltx_pipelines/utils/constants.py`
- **Wan2GP distilled:** `Wan2GP/models/ltx2/ltx_pipelines/distilled.py`
- **Wan2GP constants:** `Wan2GP/models/ltx2/ltx_pipelines/utils/constants.py`
- **Wan2GP helpers:** `Wan2GP/models/ltx2/ltx_pipelines/utils/helpers.py`
