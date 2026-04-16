#!/usr/bin/env bash
#
# Download LTX-2 19B and 2.3 22B files: Dev, standalone Distilled, LoRAs, shared components.
# Also MMAudio (video-to-audio soundtrack generation for WAN 2.2 etc.).
# Uses aria2; resumes if interrupted. Skips files that are already complete.
# Run from repo root: ./download_ltx2_aria2.sh
#
# Repos: DeepBeepMeep/LTX-2, Lightricks (22B IC-LoRAs), Kijai/LTXV2_comfy (GGUF), DeepBeepMeep/Wan2.1 (MMAudio)
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CKPTS="${SCRIPT_DIR}/wan2gp_content/ckpts"
LORAS="${SCRIPT_DIR}/wan2gp_content/loras/ltx2"
LORAS_22B="${SCRIPT_DIR}/wan2gp_content/loras/ltx2_22B"
GEMMA="${CKPTS}/gemma-3-12b-it-qat-q4_0-unquantized"
MMAUDIO="${CKPTS}/mmaudio"
BASE_URL="https://huggingface.co/DeepBeepMeep/LTX-2/resolve/main"
LIGHTRICKS_IC_URL="https://huggingface.co/Lightricks/LTX-2.3-22b-IC-LoRA-Motion-Track-Control/resolve/main"
WAN21_URL="https://huggingface.co/DeepBeepMeep/Wan2.1/resolve/main"
ARIA_OPTS="-c -x 16 -s 16 -k 1M --file-allocation=none --auto-file-renaming=false"

# 2.3 22B
KIJAI_BASE="https://huggingface.co/Kijai/LTXV2_comfy/resolve/main/diffusion_models"

download_if_needed() {
    local url="$1"
    local dir="$2"
    local file="$3"
    local path="${dir}/${file}"

    mkdir -p "$dir"
    if [[ -f "$path" ]]; then
        if [[ -f "${path}.aria2" ]]; then
            echo "[RESUME] $file ..."
        else
            echo "[SKIP] Already complete: $file"
            return 0
        fi
    else
        echo "[DOWNLOAD] $file ..."
    fi
    aria2c $ARIA_OPTS -d "$dir" -o "$file" "$url" && echo "[DONE] $file"
}

# For small config files: skip if exists (any size), else aria2
download_small() {
    local url="$1"
    local dir="$2"
    local file="$3"
    local path="${dir}/${file}"

    mkdir -p "$dir"
    if [[ -f "$path" ]]; then
        echo "[SKIP] Already present: $file"
        return 0
    fi
    echo "[DOWNLOAD] $file ..."
    aria2c $ARIA_OPTS -d "$dir" -o "$file" "$url" && echo "[DONE] $file"
}

echo "=== LTX-2 19B Dev (fp8) — Full Download ==="
echo "  Checkpoints : $CKPTS"
echo "  LoRAs       : $LORAS"
echo "  Text encoder: $GEMMA"
echo ""

# ---------------------------------------------------------------------------
echo "--- 1/12  Main transformer (21.6 GB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-dev-fp8_diffusion_model.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-dev-fp8_diffusion_model.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 2/12  Video VAE (2.45 GB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b_vae.safetensors" \
    "$CKPTS" \
    "ltx-2-19b_vae.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 3/12  Text embedding projection (1.45 GB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b_text_embedding_projection.safetensors" \
    "$CKPTS" \
    "ltx-2-19b_text_embedding_projection.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 4/12  Dev embeddings connector (1.42 GB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-dev_embeddings_connector.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-dev_embeddings_connector.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 5/12  Spatial upscaler (996 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-spatial-upscaler-x2-1.0.safetensors" \
    "$CKPTS" \
    "ltx-2-spatial-upscaler-x2-1.0.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 5b/12  Temporal upscaler (~262 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-temporal-upscaler-x2-1.0.safetensors" \
    "$CKPTS" \
    "ltx-2-temporal-upscaler-x2-1.0.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 6/12  Audio VAE (107 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b_audio_vae.safetensors" \
    "$CKPTS" \
    "ltx-2-19b_audio_vae.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 7/12  Vocoder (111 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b_vocoder.safetensors" \
    "$CKPTS" \
    "ltx-2-19b_vocoder.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 8/12  IC control LoRAs — pose / depth / canny (654 MB each) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-ic-lora-pose-control.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-ic-lora-pose-control.safetensors" \
download_if_needed \
    "${BASE_URL}/ltx-2-19b-ic-lora-depth-control.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-ic-lora-depth-control.safetensors" \
download_if_needed \
    "${BASE_URL}/ltx-2-19b-ic-lora-canny-control.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-ic-lora-canny-control.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 9/12  Distilled pipeline LoRA (7.67 GB) -> loras/ltx2/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-distilled-lora-384.safetensors" \
    "$LORAS" \
    "ltx-2-19b-distilled-lora-384.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 10/12  Standalone distilled fp8 (21.6 GB) — VRAM-friendly, no LoRA -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-distilled-fp8_diffusion_model.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-distilled-fp8_diffusion_model.safetensors" \
download_if_needed \
    "${BASE_URL}/ltx-2-19b-distilled_embeddings_connector.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-distilled_embeddings_connector.safetensors"
echo ""

# ---------------------------------------------------------------------------
# echo "--- 11/12  Distilled GGUF Q8_0 (~12 GB) — extra VRAM savings -> ckpts/ ---"
# download_if_needed \
#     "${KIJAI_BASE}/ltx-2-19b-distilled_Q8_0.gguf" \
#     "$CKPTS" \
#     "ltx-2-19b-distilled_Q8_0.gguf" \
#     "$MIN_GGUF_Q8"
# echo ""

# ---------------------------------------------------------------------------
echo "--- 12/12 Gemma-3 text encoder (13.2 GB quantized) -> ckpts/gemma-.../ ---"
download_if_needed \
    "${BASE_URL}/gemma-3-12b-it-qat-q4_0-unquantized/gemma-3-12b-it-qat-q4_0-unquantized_quanto_bf16_int8.safetensors" \
    "$GEMMA" \
    "gemma-3-12b-it-qat-q4_0-unquantized_quanto_bf16_int8.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- Gemma config files (required for tokenizer + model load) -> ckpts/gemma-.../ ---"
GBASE="${BASE_URL}/gemma-3-12b-it-qat-q4_0-unquantized"
for f in \
    added_tokens.json \
    chat_template.json \
    config.json \
    config_light.json \
    generation_config.json \
    model.safetensors.index.json \
    preprocessor_config.json \
    processor_config.json \
    special_tokens_map.json \
    tokenizer.json \
    tokenizer.model \
    tokenizer_config.json
do
    download_small "${GBASE}/${f}" "$GEMMA" "$f"
done
echo ""

# ===========================================================================
echo "=== LTX-2 2.3 22B — Full Download ==="
echo "  Checkpoints : $CKPTS"
echo "  LoRAs 22B   : $LORAS_22B"
echo ""

# ---------------------------------------------------------------------------
echo "--- 22B 1/12  Video VAE (1.45 GB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-22b_vae.safetensors" \
    "$CKPTS" \
    "ltx-2.3-22b_vae.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 22B 2/12  Text embedding projection (2.31 GB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-22b_text_embedding_projection.safetensors" \
    "$CKPTS" \
    "ltx-2.3-22b_text_embedding_projection.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 22B 3/12  Embeddings connector (4.03 GB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-22b_embeddings_connector.safetensors" \
    "$CKPTS" \
    "ltx-2.3-22b_embeddings_connector.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 22B 4/12  Spatial upscaler (996 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-spatial-upscaler-x2-1.0.safetensors" \
    "$CKPTS" \
    "ltx-2.3-spatial-upscaler-x2-1.0.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 22B 5/12  Temporal upscaler (~262 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-temporal-upscaler-x2-1.0.safetensors" \
    "$CKPTS" \
    "ltx-2.3-temporal-upscaler-x2-1.0.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 22B 6/12  Audio VAE (107 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-22b_audio_vae.safetensors" \
    "$CKPTS" \
    "ltx-2.3-22b_audio_vae.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 22B 7/12  Vocoder (258 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-22b_vocoder.safetensors" \
    "$CKPTS" \
    "ltx-2.3-22b_vocoder.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 22B 8/12  Distilled LoRA (7.61 GB) -> loras/ltx2/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-22b-distilled-lora-384.safetensors" \
    "$LORAS" \
    "ltx-2.3-22b-distilled-lora-384.safetensors"
echo ""

# ---------------------------------------------------------------------------
# 22B preload IC LoRAs — wan2gp auto-loads these from ckpts/ for Distilled
# (union-control + outpaint listed as preload_URLs in ltx2_22B_distilled.json
# and ltx2_22B_distilled_1_1.json). Must live in ckpts/, not loras/.
echo "--- 22B 9a/12  Union control LoRA (654 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors" \
    "$CKPTS" \
    "ltx-2.3-22b-ic-lora-union-control-ref0.5.safetensors"
echo ""

echo "--- 22B 9b/12  Outpaint IC LoRA (~654 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-22b-ic-lora-outpaint.safetensors" \
    "$CKPTS" \
    "ltx-2.3-22b-ic-lora-outpaint.safetensors"
echo ""

echo "--- 22B 10/12  Motion track control LoRA (654 MB) -> loras/ltx2_22B/ ---"
download_if_needed \
    "${LIGHTRICKS_IC_URL}/ltx-2.3-22b-ic-lora-motion-track-control-ref0.5.safetensors" \
    "$LORAS_22B" \
    "ltx-2.3-22b-ic-lora-motion-track-control-ref0.5.safetensors"
echo ""

# ---------------------------------------------------------------------------
echo "--- 22B 11/12  Dev transformer quanto int8 (19.4 GB) — fits 32GB VRAM -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-22b-dev_diffusion_model_quanto_int8.safetensors" \
    "$CKPTS" \
    "ltx-2.3-22b-dev_diffusion_model_quanto_int8.safetensors"
echo ""

# ---------------------------------------------------------------------------
# CelebV-HQ ID-LoRA: preload_URLs of ltx2_22B.json (Dev 22B) AND inherited by
# any LTX-2.3 22B finetune that declares `preload_URLs: "ltx2_22B"` — e.g.
# 10Eros_LTX2.3_fp8, ltx2310eros_beta, etc. get_model_recursive_prop
# (wgp.py:2391) walks the string reference into the Dev defaults.
echo "--- 22B ID   CelebV-HQ ID-LoRA (~654 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/id-lora-celebvhq-ltx2.3.safetensors" \
    "$CKPTS" \
    "id-lora-celebvhq-ltx2.3.safetensors"
echo ""

# ---------------------------------------------------------------------------
# echo "--- 22B full distilled (38 GB) — needs 40GB+ VRAM, skip for 32GB ---"
# download_if_needed \
#     "${BASE_URL}/ltx-2.3-22b-distilled_diffusion_model.safetensors" \
#     "$CKPTS" \
#     "ltx-2.3-22b-distilled_diffusion_model.safetensors" \
#     "$MIN_MODEL_22B"
# echo ""

echo "--- 22B 12/12  Standalone distilled quanto int8 (19.4 GB) — fits 32GB VRAM -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2.3-22b-distilled_diffusion_model_quanto_int8.safetensors" \
    "$CKPTS" \
    "ltx-2.3-22b-distilled_diffusion_model_quanto_int8.safetensors"
echo ""

# ===========================================================================
echo "=== MMAudio — Video-to-Audio Soundtrack Generation (WAN 2.2 etc.) ==="
echo "  Output : $MMAUDIO"
echo "  Enable in Configuration → Extensions → MMAudio Soundtrack Generation"
echo ""

echo "--- MMAudio 1/4  Synchformer (~475 MB) -> ckpts/mmaudio/ ---"
download_if_needed \
    "${WAN21_URL}/mmaudio/synchformer_state_dict.pth" \
    "$MMAUDIO" \
    "synchformer_state_dict.pth"
echo ""

echo "--- MMAudio 2/4  VAE v1-44 (~100 MB) -> ckpts/mmaudio/ ---"
download_if_needed \
    "${WAN21_URL}/mmaudio/v1-44.pth" \
    "$MMAUDIO" \
    "v1-44.pth"
echo ""

echo "--- MMAudio 3/4  Standard model (~2 GB) -> ckpts/mmaudio/ ---"
download_if_needed \
    "${WAN21_URL}/mmaudio/mmaudio_large_44k_v2.pth" \
    "$MMAUDIO" \
    "mmaudio_large_44k_v2.pth"
echo ""

echo "--- MMAudio 4/4  Gold/NSFW model (~2 GB) -> ckpts/mmaudio/ ---"
download_if_needed \
    "${WAN21_URL}/mmaudio/mmaudio_large_44k_gold_8.5k_final_fp16.safetensors" \
    "$MMAUDIO" \
    "mmaudio_large_44k_gold_8.5k_final_fp16.safetensors"
echo ""

echo "=== Download complete ==="
echo "  Launch wan2gp and select:"
echo "    19B: LTX-2 Dev 19B | LTX-2 Distilled 19B | LTX-2 Distilled GGUF Q8_0"
echo "    22B: LTX-2 2.3 Dev 22B | LTX-2 2.3 Distilled 22B"
echo "  MMAudio: Enable in Configuration → Extensions for video soundtrack generation"
