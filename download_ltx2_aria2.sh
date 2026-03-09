#!/usr/bin/env bash
#
# Download LTX-2 19B files: Dev (fp8), standalone Distilled (fp8), and Distilled GGUF Q8_0.
# Uses aria2; resumes if interrupted. Skips files that are already complete.
# Run from repo root: ./download_ltx2_aria2.sh
#
# Repos: DeepBeepMeep/LTX-2, Kijai/LTXV2_comfy (GGUF)
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CKPTS="${SCRIPT_DIR}/wan2gp_content/ckpts"
LORAS="${SCRIPT_DIR}/wan2gp_content/loras/ltx2"
GEMMA="${CKPTS}/gemma-3-12b-it-qat-q4_0-unquantized"
BASE_URL="https://huggingface.co/DeepBeepMeep/LTX-2/resolve/main"
ARIA_OPTS="-c -x 16 -s 16 -k 1M --file-allocation=none --auto-file-renaming=false"

# Minimum sizes (bytes) to consider a file complete; skip if existing file >= this
MIN_MODEL=$((20 * 1024 * 1024 * 1024))    # 21.6 GB transformer
MIN_GEMMA=$((12 * 1024 * 1024 * 1024))    # 13.2 GB text encoder (quantized)
MIN_LORA=$((7  * 1024 * 1024 * 1024))     # 7.67 GB distilled pipeline lora
MIN_TEP=$((1   * 1024 * 1024 * 1024))     # 1.45 GB text embedding projection
MIN_CONN=$((1  * 1024 * 1024 * 1024))     # 1.42 GB embeddings connector
MIN_VAE=$((2   * 1024 * 1024 * 1024))     # 2.45 GB video VAE
MIN_UPSCALER=$((900 * 1024 * 1024))       # 996 MB spatial upscaler
MIN_IC_LORA=$((600 * 1024 * 1024))        # 654 MB IC control loras
MIN_SMALL=$((100 * 1024 * 1024))          # 107-111 MB audio VAE / vocoder
MIN_DISTILLED=$((20 * 1024 * 1024 * 1024)) # 21.6 GB standalone distilled fp8
MIN_GGUF_Q8=$((18 * 1024 * 1024 * 1024))  # ~20 GB distilled GGUF Q8_0
KIJAI_BASE="https://huggingface.co/Kijai/LTXV2_comfy/resolve/main/diffusion_models"

download_if_needed() {
    local url="$1"
    local dir="$2"
    local file="$3"
    local min_size="$4"
    local path="${dir}/${file}"

    mkdir -p "$dir"
    if [[ -f "$path" ]]; then
        local size
        size=$(stat -c%s "$path" 2>/dev/null || echo 0)
        if [[ $size -ge $min_size ]]; then
            echo "[SKIP] Already complete: $file"
            return 0
        fi
        if [[ ! -f "${path}.aria2" ]]; then
            echo "[REMOVE] Incomplete/foreign $file, re-downloading..."
            rm -f "$path"
        else
            echo "[RESUME] $file ..."
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
    "ltx-2-19b-dev-fp8_diffusion_model.safetensors" \
    "$MIN_MODEL"
echo ""

# ---------------------------------------------------------------------------
echo "--- 2/12  Video VAE (2.45 GB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b_vae.safetensors" \
    "$CKPTS" \
    "ltx-2-19b_vae.safetensors" \
    "$MIN_VAE"
echo ""

# ---------------------------------------------------------------------------
echo "--- 3/12  Text embedding projection (1.45 GB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b_text_embedding_projection.safetensors" \
    "$CKPTS" \
    "ltx-2-19b_text_embedding_projection.safetensors" \
    "$MIN_TEP"
echo ""

# ---------------------------------------------------------------------------
echo "--- 4/12  Dev embeddings connector (1.42 GB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-dev_embeddings_connector.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-dev_embeddings_connector.safetensors" \
    "$MIN_CONN"
echo ""

# ---------------------------------------------------------------------------
echo "--- 5/12  Spatial upscaler (996 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-spatial-upscaler-x2-1.0.safetensors" \
    "$CKPTS" \
    "ltx-2-spatial-upscaler-x2-1.0.safetensors" \
    "$MIN_UPSCALER"
echo ""

# ---------------------------------------------------------------------------
echo "--- 6/12  Audio VAE (107 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b_audio_vae.safetensors" \
    "$CKPTS" \
    "ltx-2-19b_audio_vae.safetensors" \
    "$MIN_SMALL"
echo ""

# ---------------------------------------------------------------------------
echo "--- 7/12  Vocoder (111 MB) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b_vocoder.safetensors" \
    "$CKPTS" \
    "ltx-2-19b_vocoder.safetensors" \
    "$MIN_SMALL"
echo ""

# ---------------------------------------------------------------------------
echo "--- 8/12  IC control LoRAs — pose / depth / canny (654 MB each) -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-ic-lora-pose-control.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-ic-lora-pose-control.safetensors" \
    "$MIN_IC_LORA"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-ic-lora-depth-control.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-ic-lora-depth-control.safetensors" \
    "$MIN_IC_LORA"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-ic-lora-canny-control.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-ic-lora-canny-control.safetensors" \
    "$MIN_IC_LORA"
echo ""

# ---------------------------------------------------------------------------
echo "--- 9/12  Distilled pipeline LoRA (7.67 GB) -> loras/ltx2/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-distilled-lora-384.safetensors" \
    "$LORAS" \
    "ltx-2-19b-distilled-lora-384.safetensors" \
    "$MIN_LORA"
echo ""

# ---------------------------------------------------------------------------
echo "--- 10/12  Standalone distilled fp8 (21.6 GB) — VRAM-friendly, no LoRA -> ckpts/ ---"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-distilled-fp8_diffusion_model.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-distilled-fp8_diffusion_model.safetensors" \
    "$MIN_DISTILLED"
download_if_needed \
    "${BASE_URL}/ltx-2-19b-distilled_embeddings_connector.safetensors" \
    "$CKPTS" \
    "ltx-2-19b-distilled_embeddings_connector.safetensors" \
    "$MIN_CONN"
echo ""

# ---------------------------------------------------------------------------
echo "--- 11/12  Distilled GGUF Q8_0 (~12 GB) — extra VRAM savings -> ckpts/ ---"
download_if_needed \
    "${KIJAI_BASE}/ltx-2-19b-distilled_Q8_0.gguf" \
    "$CKPTS" \
    "ltx-2-19b-distilled_Q8_0.gguf" \
    "$MIN_GGUF_Q8"
echo ""

# ---------------------------------------------------------------------------
echo "--- 12/12 Gemma-3 text encoder (13.2 GB quantized) -> ckpts/gemma-.../ ---"
download_if_needed \
    "${BASE_URL}/gemma-3-12b-it-qat-q4_0-unquantized/gemma-3-12b-it-qat-q4_0-unquantized_quanto_bf16_int8.safetensors" \
    "$GEMMA" \
    "gemma-3-12b-it-qat-q4_0-unquantized_quanto_bf16_int8.safetensors" \
    "$MIN_GEMMA"
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

echo "=== LTX-2 download complete ==="
echo "  Launch wan2gp and select:"
echo "    - LTX-2 Dev 19B (default, full features)"
echo "    - LTX-2 Distilled 19B (VRAM-friendly, no LoRA)"
echo "    - LTX-2 Distilled GGUF Q8_0 (extra VRAM savings)"
