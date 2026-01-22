# Forge Content Directory

This directory contains all your custom Stable Diffusion models and resources for WebUI Forge.

## Directory Structure:

- **models/** - Stable Diffusion checkpoints (.safetensors, .ckpt)
- **loras/** - LoRA files for fine-tuning
- **embeddings/** - Textual Inversion embeddings
- **vae/** - VAE (Variational AutoEncoder) models
- **controlnet/** - ControlNet models
- **upscalers/** - Upscaler models (ESRGAN, RealESRGAN, etc.)

## How It Works:

1. Place your files in these directories
2. Run the launcher script (`./run-forge-conda.sh`)
3. Files are automatically symlinked into the Forge repository
4. Symlinks are gitignored (won't interfere with git updates)

## Benefits:

- All custom content in one organized location
- Separate from repository (survives git updates)
- Easy to backup/restore
- Compatible with wan2gp_content/ structure
- No repository modifications needed

