# Forge Content Directory

This directory contains all your custom models, LoRAs, and configurations for Stable Diffusion WebUI Forge.

## Directory Layout

All directories use Forge's actual directory names for consistency:

- `Stable-diffusion/` - Stable Diffusion checkpoints (.safetensors, .ckpt)
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/Stable-diffusion/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/Stable-diffusion/`
  - Place your SD checkpoints here
  - Auto-downloaded models will be saved here

- `Lora/` - LoRA files for fine-tuning
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/Lora/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/Lora/`
  - Place your LoRA .safetensors files here

- `embeddings/` - Textual Inversion embeddings
  - Always symlinked into `sd-webui-forge-classic/embeddings/` (root level)
  - Place your embedding files here

- `VAE/` - VAE (Variational AutoEncoder) models
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/VAE/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/VAE/`
  - Place your VAE files here

- `ControlNet/` - ControlNet models
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/ControlNet/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/ControlNet/`
  - Place your ControlNet models here

- `ESRGAN/` - Upscaler models (ESRGAN, RealESRGAN, etc.)
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/ESRGAN/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/ESRGAN/`
  - Place your upscaler models here

- `text_encoder/` - Text encoder models
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/text_encoder/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/text_encoder/`
  - Place your text encoder models here

- `Codeformer/` - CodeFormer face restoration models
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/Codeformer/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/Codeformer/`
  - Place your CodeFormer models here

- `GFPGAN/` - GFPGAN face restoration models (used by adetailer)
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/GFPGAN/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/GFPGAN/`
  - Place your GFPGAN models here

- `ControlNetPreprocessor/` - ControlNet preprocessor/annotator models
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/ControlNetPreprocessor/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/ControlNetPreprocessor/`
  - Place your ControlNet preprocessor models here
  - Passed via `--controlnet-preprocessor-models-dir` if directory has content

- `diffusers/` - Diffusers format models (Hugging Face format)
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/diffusers/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/diffusers/`
  - Auto-created by Forge, used for diffusers format models

- `adetailer/` - ADetailer extension models
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/adetailer/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/adetailer/`
  - Place your ADetailer models here

- `hypernetworks/` - Hypernetwork models (A1111 feature, may not be fully supported in Forge)
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/hypernetworks/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/hypernetworks/`
  - Place your hypernetwork models here

- `deepbooru/` - Deepbooru interrogator models
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/deepbooru/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/deepbooru/`
  - Place your Deepbooru models here

- `karlo/` - Karlo models (if supported)
  - If MODELS_DIR is set: symlinked into `MODELS_DIR/karlo/`
  - Otherwise: symlinked into `sd-webui-forge-classic/models/karlo/`
  - Place your Karlo models here

## How It Works

This directory (`forge_content/`) is the single source of truth for all custom content.
The launcher creates directory symlinks to this location:
- If `MODELS_DIR` is configured: symlinks go into `MODELS_DIR/` (for external storage)
- If `MODELS_DIR` is empty: symlinks go into WebUI defaults (repository location)

This keeps all your custom content in one organized location while appearing
natively in the application directory, regardless of where it's physically stored.

## Benefits

- All custom content in one place
- Separate from repository (survives git updates)
- Auto-downloaded models go to external storage
- Easy to backup/restore
- Compatible with wan2gp_content/ structure

## Notes

- The launcher automatically creates and links these directories on first run
- No configuration needed - just place files in the appropriate subdirectory
- Symlinks are created automatically on every launch
