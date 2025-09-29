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
- **SageAttention Compilation** - Automatic build from source for video generation optimization
- **Branch Detection** - Intelligent handling of different repository branches
- **Save Path Management** - Configurable video and image output directories

### Configuration Options

Edit `wan2gp-config.sh` to customize:

```bash
# Cache and cleanup
AUTO_CACHE_CLEANUP=false
CACHE_SIZE_THRESHOLD=100

# System paths  
TEMP_CACHE_DIR="/path/to/temp"
CONDA_EXE="/opt/miniconda3/bin/conda"

# Save paths (fallback if save_path.json missing)
SCRIPT_SAVE_PATH="/path/to/videos"
SCRIPT_IMAGE_SAVE_PATH="/path/to/images"

# Performance
DEFAULT_SAGE_VERSION="2"  # or "3" for Blackwell GPUs
DEFAULT_ENABLE_TCMALLOC=true
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

# Use SageAttention 3 (Blackwell GPUs)
./run-wan2gp-conda.sh --sage3

# Skip git updates
./run-wan2gp-conda.sh --no-git-update
```

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

- **Models Directory Management** - Flexible model storage configuration
- **Output Directory Control** - Organized image generation output
- **JSON Configuration Sync** - Automatic WebUI config.json updates
- **Restart Loop Support** - Handles WebUI restarts gracefully

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
