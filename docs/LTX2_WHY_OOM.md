# Why LTX-2 OOMs on 64GB RAM + 32GB VRAM (and how to fix it)

## Root cause: you're using the heaviest configuration

You're running **LTX-2 Dev 19B** with the **distilled LoRA** pre-loaded. That is the most VRAM-heavy setup:

| Component | Size | Notes |
|-----------|------|-------|
| Dev base (fp8) | 21.6 GB | `ltx-2-19b-dev-fp8_diffusion_model.safetensors` |
| Distilled LoRA | 7.67 GB | `ltx-2-19b-distilled-lora-384.safetensors` |
| **Total transformer** | **~29.3 GB** | Before VAE, text encoder, activations |

The two-stage pipeline loads the LoRA for **both** stage 1 and stage 2, so you see:
`loras/ltx2/ltx-2-19b-distilled-lora-384.safetensors,loras/ltx2/ltx-2-19b-distilled-lora-384.safetensors`

With 32GB VRAM, 29.3GB for model + LoRA leaves almost no headroom for activations, VAE, and swapping. Hence OOM.

## How others run LTX-2 on 12–24GB

They use the **standalone distilled model** (LTX-2 Distilled 19B), which:

- Uses `ltx-2-19b-distilled-fp8_diffusion_model.safetensors` (21.6 GB) — **no LoRA**
- Saves ~7.67 GB VRAM vs dev + LoRA
- Uses a single-stage pipeline (DistilledPipeline)
- Runs in ~8 steps instead of 40
- Avoids the “dirty mirror” quality issues of dev + distilled LoRA (GitHub #1312)

## Fix: switch to LTX-2 Distilled 19B

1. **Download the distilled model** (if not already present):

   ```bash
   cd /home/g/wan2gp
   CKPTS="wan2gp_content/ckpts"
   BASE="https://huggingface.co/DeepBeepMeep/LTX-2/resolve/main"
   aria2c -c -x 16 -s 16 -k 1M --file-allocation=none -d "$CKPTS" \
     "$BASE/ltx-2-19b-distilled-fp8_diffusion_model.safetensors"
   aria2c -c -x 16 -s 16 -k 1M --file-allocation=none -d "$CKPTS" \
     "$BASE/ltx-2-19b-distilled_embeddings_connector.safetensors"
   ```

   VAE, text projection, vocoder, etc. are shared with dev; only transformer + embeddings connector differ.

2. **In Wan2GP UI**: change model from **"LTX-2 Dev 19B"** to **"LTX-2 Distilled 19B"**.

3. **Optional**: keep profile 4 and `perc_reserved_mem_max=0.25` for stability.

## Summary

| Model | VRAM (approx) | Pipeline | Steps |
|-------|----------------|----------|-------|
| LTX-2 Dev 19B + distilled LoRA | ~29+ GB | Two-stage | 40 |
| **LTX-2 Distilled 19B** (standalone) | **~22 GB** | Single-stage | 8 |

The download script (`download_ltx2_aria2.sh`) was written for the dev + LoRA setup. For 32GB VRAM, the standalone distilled model is the better choice.
