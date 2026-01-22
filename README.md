# Wan2GP Launcher Collection

A collection of sophisticated conda environment launchers for AI video and image generation tools.

> **⚠️ CONDA REQUIRED**: These launchers require Conda/Miniconda/Anaconda to be installed. They will not work with regular Python virtual environments or system Python. [Download Miniconda here](https://docs.conda.io/en/latest/miniconda.html).

## 🚀 What's Included

This repository provides production-ready conda launchers for:

- **[Wan2GP](#wan2gp-launcher)** - AI Video Generation (deepbeepmeep/Wan2GP)
- **[Stable Diffusion WebUI Forge](#forge-launcher)** - AI Image Generation (lllyasviel/stable-diffusion-webui-forge)

## ✨ Key Features

All launchers share these robust improvements:

- **🔍 Smart Conda Detection** - Checks PATH first, falls back to configured location
- **⚙️ External Configuration** - Customize settings without editing scripts
- **🛠️ Enhanced Error Messages** - Multiple solution paths for troubleshooting
- **🔄 Automatic Setup** - Auto-clone repositories and create environments
- **🧹 Cache Management** - Configurable cleanup with size thresholds
- **🎯 Path Management** - Flexible models, output, and temp directory handling
- **⚡ Performance Optimization** - TCMalloc support and GPU detection

---

## 🎬 Wan2GP Launcher

### Quick Start

```bash
# Copy and customize configuration
cp wan2gp-config.sh.sample wan2gp-config.sh
# Edit wan2gp-config.sh with your preferences

# Run the launcher
./run-wan2gp-conda.sh
```

### Features

- **Repository Selection** - Choose between official or Gunther-Schulz enhanced fork
- **Automatic Branch Switching** - Configurable branch selection with auto-updates
- **SageAttention Support** - Auto-detects GPU and installs optimal version (v2 or v3)
  - SageAttention 2.2.0 for RTX 30xx/40xx (GitHub)
  - SageAttention3 for RTX 50xx Blackwell (GitHub, auto-compiled)
- **Content Organization** - Unified wan2gp_content/ structure for models, LoRAs, finetunes
- **Smart Dependencies** - Auto-detects requirements.txt changes on branch switches
- **Package Verification** - Validates and auto-fixes version mismatches
- **Save Path Management** - Configurable video and image output directories

### Content Organization

The launcher automatically manages a unified content structure:

```
wan2gp_content/
  ├── ckpts/                 # Checkpoint files (auto-downloads go here)
  ├── finetunes/             # Finetune JSON files (auto-symlinked)
  ├── loras/                 # General LoRA files (auto-symlinked)
  ├── loras_flux/            # Flux-specific LoRAs (auto-symlinked)
  ├── loras_hunyuan/         # Hunyuan LoRAs (auto-symlinked)
  ├── loras_hunyuan_i2v/     # Hunyuan I2V LoRAs (auto-symlinked)
  ├── loras_i2v/             # I2V LoRAs (auto-symlinked)
  ├── loras_ltxv/            # LTXV LoRAs (auto-symlinked)
  └── loras_qwen/            # Qwen LoRAs (auto-symlinked)
```

**Benefits:**
- All custom content in one organized location
- Separate from repository (survives git updates)
- Auto-downloaded models go to external storage
- Easy to backup/restore
- Compatible with future forge_content/ installation

**No configuration needed** - just create the directories and the launcher handles syncing automatically.

### Configuration Options

Edit `wan2gp-config.sh` to customize:

```bash
# Cache and cleanup
AUTO_CACHE_CLEANUP=false
CACHE_SIZE_THRESHOLD=100

# Git update behavior
AUTO_GIT_UPDATE=true  # Required for automatic branch switching

# System paths  
TEMP_CACHE_DIR="/path/to/temp"
CONDA_EXE="/opt/miniconda3/bin/conda"

# Save paths (fallback if save_path.json missing)
SCRIPT_SAVE_PATH="/path/to/videos"
SCRIPT_IMAGE_SAVE_PATH="/path/to/images"

# SageAttention configuration
DEFAULT_SAGE_VERSION="auto"  # "auto" = Auto-detect based on GPU
                             # "2" = Force SageAttention 2.2.0 (RTX 30xx/40xx)
                             # "3" = Force SageAttention3 (RTX 50xx Blackwell)
                             # "none" = Disable SageAttention
AUTO_UPGRADE_SAGE=false      # Auto-upgrade when old version detected

# Performance
DEFAULT_ENABLE_TCMALLOC=true

# Repository configuration (for custom fork)
CUSTOM_REPO_URL="https://github.com/Gunther-Schulz/Wan2GP.git"
CUSTOM_REPO_BRANCH="main"    # Branch to use from custom fork
```

### Usage Examples

```bash
# Default mode (Image-to-Video)
./run-wan2gp-conda.sh

# Text-to-Video mode
./run-wan2gp-conda.sh --t2v

# Force cache cleanup
./run-wan2gp-conda.sh --clean-cache

# Rebuild environment
./run-wan2gp-conda.sh --rebuild-env

# Force SageAttention3 (Blackwell RTX 50xx, auto-compiles from GitHub)
./run-wan2gp-conda.sh --sage3

# Force SageAttention 2.2.0 (RTX 30xx/40xx)
./run-wan2gp-conda.sh --sage2

# Skip git updates
./run-wan2gp-conda.sh --no-git-update
```

### SageAttention Versions

The launcher **auto-detects your GPU** and installs the optimal version:

#### **SageAttention 2.2.0 (Stable)**
- **Source**: GitHub (thu-ml/SageAttention) - automatically compiled
- **Requirements**: Python ≥3.9, PyTorch ≥2.0, CUDA ≥12.0
- **Performance**: 2-5x speedup with stable performance
- **Auto-selected for**: RTX 3060/3090, RTX 4060/4090, A100, H100
- **Features**: Low-bit attention, per-thread quantization, outlier smoothing
- **Compilation**: Multi-threaded (uses 75% of CPU cores)

#### **SageAttention3 (Blackwell Optimized)**
- **Source**: GitHub (thu-ml/SageAttention) - automatically compiled
- **Requirements**: Python ≥3.13, PyTorch ≥2.8.0, CUDA ≥12.8
- **Performance**: Up to 5x speedup with FP4 Tensor Cores
- **Auto-selected for**: RTX 5070/5080/5090 (Blackwell architecture)
- **Features**: Microscaling FP4 attention for next-gen GPUs
- **Compilation**: Optimized for sm_120 (Blackwell compute capability)

**Auto-Detection:**
- Set `DEFAULT_SAGE_VERSION="auto"` (default) for automatic GPU detection
- Override with `--sage2` or `--sage3` command-line flags
- Launcher handles all compilation automatically

---

## 🎨 Forge Launcher

### Quick Start

```bash
# Copy and customize configuration
cp forge-config.sh.sample forge-config.sh
# Edit forge-config.sh with your preferences

# Run the launcher
./run-forge-conda.sh
```

### Features

- **External Content Organization** - Unified forge_content/ structure for all custom models
- **SageAttention Support** - Auto-detects GPU and installs optimal version (v2 or v3)
- **Content Auto-Sync** - Models, LoRAs, VAE, ControlNet, and upscalers automatically symlinked
- **Models Directory Management** - Flexible model storage configuration
- **Output Directory Control** - Organized image generation output
- **JSON Configuration Sync** - Automatic WebUI config.json updates
- **Restart Loop Support** - Handles WebUI restarts gracefully

### Content Organization

The launcher automatically manages a unified content structure:

```
forge_content/
  ├── models/      - SD checkpoints (auto-symlinked)
  ├── loras/       - LoRA files (auto-symlinked)
  ├── embeddings/  - Textual Inversions (auto-symlinked)
  ├── vae/         - VAE models (auto-symlinked)
  ├── controlnet/  - ControlNet models (auto-symlinked)
  └── upscalers/   - Upscaler models (auto-symlinked)
```

**Benefits:**
- All custom content in one organized location
- Separate from repository (survives git updates)
- Auto-synced on every launch
- Easy to backup/restore
- Compatible with wan2gp_content/ structure

**No configuration needed** - just create the directories and the launcher handles syncing automatically.

### Configuration Options

Edit `forge-config.sh` to customize:

```bash
# Directory configuration
MODELS_DIR_DEFAULT="/path/to/models"
CUSTOM_MODELS_DIR="/path/to/custom/models"
OUTPUT_DIR="/path/to/output"

# Cache and performance
AUTO_CACHE_CLEANUP=true
TEMP_CACHE_DIR="/path/to/temp"
DEFAULT_ENABLE_TCMALLOC=true

# Environment
CONDA_ENV_NAME="sd-webui-forge"
CONDA_ENV_FILE="environment-forge.yml"
```

### Usage Examples

```bash
# Default setup
./run-forge-conda.sh

# Use custom models directory
./run-forge-conda.sh --use-custom-dir
# or shorthand:
./run-forge-conda.sh -c

# Override models directory
./run-forge-conda.sh --models-dir /path/to/models

# Override output directory
./run-forge-conda.sh --output-dir /path/to/output

# Force cache cleanup
./run-forge-conda.sh --clean-cache

# Disable TCMalloc
./run-forge-conda.sh --disable-tcmalloc
```

---

## 🛠️ Installation & Setup

### Prerequisites

**Required:**
- **Linux** (tested on CachyOS/Arch, should work on Ubuntu/Debian/Fedora)
- **Git** - For repository cloning and updates
- **Conda/Miniconda/Anaconda** - **REQUIRED** for Python environment management

**Conda Installation:**
```bash
# Option 1: Download and install Miniconda (recommended)
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh

# Option 2: Package manager installation
# Arch/CachyOS/Manjaro:
sudo pacman -S miniconda3

# Ubuntu/Debian (via snap):
sudo snap install micromamba --classic

# Fedora:
sudo dnf install conda
```

**Note:** These launchers are specifically designed for conda environments and will not work with regular Python virtual environments or system Python.

### Installation

1. **Clone this repository:**
   ```bash
   git clone https://github.com/Gunther-Schulz/wan2gp-launcher.git
   cd wan2gp-launcher
   ```

2. **Choose your launcher and copy the sample config:**
   ```bash
   # For Wan2GP
   cp wan2gp-config.sh.sample wan2gp-config.sh
   
   # For Forge
   cp forge-config.sh.sample forge-config.sh
   ```

3. **Edit the configuration file** with your preferred settings

4. **Run the launcher:**
   ```bash
   # Wan2GP
   ./run-wan2gp-conda.sh
   
   # Forge
   ./run-forge-conda.sh
   ```

The launcher will automatically:
- Detect or install conda
- Clone the target repository
- Create the conda environment
- Install all dependencies
- Launch the application

## 🔧 Advanced Configuration

### Conda Detection

The launchers use smart conda detection:

1. **First**: Check if `conda` is in PATH
2. **Second**: Use configured `CONDA_EXE` path
3. **Fail**: Provide helpful error with multiple solutions

### Cache Management

Configure automatic cache cleanup:

```bash
AUTO_CACHE_CLEANUP=true
CACHE_SIZE_THRESHOLD=100  # MB
TEMP_CACHE_DIR="/custom/temp/path"
```

### GPU Support

Automatic GPU detection and optimization:
- **NVIDIA**: CUDA support
- **AMD Navi 1/2**: HSA_OVERRIDE_GFX_VERSION
- **AMD Renoir**: Specific GFX version
- **TCMalloc**: Memory optimization

## 🐛 Troubleshooting

### Common Issues

**Conda not found:**
- Install conda/miniconda
- Add conda to PATH
- Update `CONDA_EXE` in config file

**Environment creation fails:**
- Check internet connection
- Verify disk space
- Try: `conda config --add channels conda-forge`

**Permission errors:**
- Check directory permissions
- Ensure write access to output directories

**Git clone fails:**
- Check internet connection
- Verify GitHub access
- Check disk space

**SageAttention3 installation fails:**
- Verify Python ≥3.13: `python --version`
- Verify PyTorch ≥2.8.0: `python -c "import torch; print(torch.__version__)"`
- Check CUDA ≥12.8: `nvcc --version`
- Repository may be gated - request access at HuggingFace
- Falls back to SageAttention 2.2.0 automatically

**SageAttention compilation errors:**
- Ensure CUDA toolkit is installed
- Check available disk space (compilation requires 5-10GB)
- Check build logs in `/tmp/sageattention_wan2gp_build.log`
- Compilation uses 75% of CPU cores automatically (no configuration needed)

### Getting Help

Each launcher provides detailed error messages with multiple solution paths. If you encounter issues:

1. Read the error message carefully
2. Try the suggested solutions
3. Check the configuration file
4. Ensure all prerequisites are installed

## 📝 License

This project is licensed under the same terms as the underlying projects it supports.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## 🙏 Acknowledgments

- **deepbeepmeep** - Original Wan2GP project
- **lllyasviel** - Stable Diffusion WebUI Forge
- **Gunther-Schulz** - Enhanced Wan2GP fork with Mega-v3 support
- **Community** - For testing and feedback

---

## 📊 Repository Stats

- **Languages**: Bash, YAML
- **Launchers**: 2 (Wan2GP, Forge)
- **Features**: Smart detection, auto-setup, configuration management
- **Compatibility**: Linux (Arch, Ubuntu, Debian, Fedora, CachyOS)
