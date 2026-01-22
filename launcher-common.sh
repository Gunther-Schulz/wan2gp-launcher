#!/bin/bash
#########################################################
# Launcher Common Library
# Shared functions for wan2gp and forge conda launchers
#########################################################

# Color definitions (can be used by both scripts)
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#########################################################
# Constants
#########################################################

# SageAttention repository URL (used in multiple places)
SAGE_REPO_URL="https://github.com/thu-ml/SageAttention.git"

# Temporary directory paths (centralized for easy modification)
SAGE_TEMP_DIR="/tmp/SageAttention"
SAGE_UPDATE_DIR="/tmp/SageAttention_update"
SAGE_INSTALL_DIR="/tmp/SageAttention_wan2gp"
SAGE_BUILD_LOG="/tmp/sageattention_wan2gp_build.log"
SAGE3_CLONE_LOG="/tmp/sage3_clone.log"
SAGE_INITIAL_LOG="/tmp/sageattention_wan2gp_initial.log"
SAGE3_INITIAL_LOG="/tmp/sageattention3_wan2gp_initial.log"

#########################################################
# Helper Functions
#########################################################

# Helper function: Calculate optimal parallel jobs for compilation
# Returns 75% of CPU cores, minimum 4
# Usage: PARALLEL_JOBS=$(calculate_parallel_jobs)
calculate_parallel_jobs() {
    local nproc=$(nproc)
    local jobs=$(( nproc * 3 / 4 ))
    echo $(( jobs < 4 ? 4 : jobs ))
}

# Helper function: Set environment variables for parallel compilation
# Usage: set_parallel_build_env PARALLEL_JOBS
set_parallel_build_env() {
    local jobs="$1"
    export MAX_JOBS="${jobs}"
    export CMAKE_BUILD_PARALLEL_LEVEL="${jobs}"
    export MAKEFLAGS="-j${jobs}"
    export NVCC_APPEND_FLAGS="--threads ${jobs}"
}

# Helper function: Uninstall SageAttention versions
# Usage: uninstall_sageattention [version]
#   version: "all" (default) = uninstall all versions
#            "2" = uninstall v2 only
#            "3" = uninstall v3 only
uninstall_sageattention() {
    local version="${1:-all}"
    case "$version" in
        "2")
            pip uninstall -y sageattention 2>/dev/null || true
            ;;
        "3")
            pip uninstall -y sageattention sageattn3 2>/dev/null || true
            ;;
        *)
            pip uninstall -y sageattention sageattn3 2>/dev/null || true
            ;;
    esac
}

# Helper function: Activate conda environment with error handling
# Usage: activate_conda_env [suppress_errors]
#   suppress_errors: "quiet" = suppress error messages
activate_conda_env() {
    local quiet="${1:-}"
    if [[ "$quiet" == "quiet" ]]; then
        eval "$("${CONDA_EXE}" shell.bash hook)" 2>/dev/null
        conda activate "${ENV_NAME}" 2>/dev/null
    else
        eval "$("${CONDA_EXE}" shell.bash hook)"
        conda activate "${ENV_NAME}"
    fi
}

# Helper function: Detect GPU architecture and capabilities
# Sets global variables: GPU_VENDOR, GPU_NAME, GPU_COMPUTE_CAP, SUPPORTS_SAGE3
# Usage: detect_gpu
detect_gpu() {
    GPU_VENDOR="unknown"
    GPU_NAME="unknown"
    GPU_COMPUTE_CAP=""
    SUPPORTS_SAGE3=false
    
    # Try nvidia-smi for NVIDIA GPUs
    if command -v nvidia-smi &> /dev/null; then
        GPU_VENDOR="nvidia"
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        
        # Detect Blackwell (RTX 50xx series) - compute capability 12.0
        if echo "$GPU_NAME" | grep -qiE "RTX 50[0-9]{2}|Blackwell"; then
            GPU_COMPUTE_CAP="12.0"
            SUPPORTS_SAGE3=true
        # Ada Lovelace (RTX 40xx series) - compute capability 8.9
        elif echo "$GPU_NAME" | grep -qiE "RTX 40[0-9]{2}|L40|Ada"; then
            GPU_COMPUTE_CAP="8.9"
            SUPPORTS_SAGE3=false
        # Ampere (RTX 30xx series, A100, etc.) - compute capability 8.0
        elif echo "$GPU_NAME" | grep -qiE "RTX 30[0-9]{2}|A100|A40|A30|A10|Ampere"; then
            GPU_COMPUTE_CAP="8.0"
            SUPPORTS_SAGE3=false
        fi
    # Try lspci for AMD/Intel GPUs
    elif command -v lspci &> /dev/null; then
        local gpu_info=$(lspci | grep -i "vga\|3d\|display" | head -1)
        if echo "$gpu_info" | grep -qi "amd\|radeon"; then
            GPU_VENDOR="amd"
            GPU_NAME=$(echo "$gpu_info" | sed 's/.*: //')
        elif echo "$gpu_info" | grep -qi "intel"; then
            GPU_VENDOR="intel"
            GPU_NAME=$(echo "$gpu_info" | sed 's/.*: //')
        fi
    fi
}

# Helper function: Get recommended SageAttention version based on GPU
# Usage: recommended_sage_version=$(get_recommended_sage_version)
# Returns: "3" for Blackwell GPUs, "2" for others
get_recommended_sage_version() {
    detect_gpu
    if [[ "$SUPPORTS_SAGE3" == "true" ]]; then
        echo "3"
    else
        echo "2"
    fi
}

# Helper function: Check if Python version supports SageAttention3
# Returns: 0 if Python >= 3.13, 1 otherwise
check_python_sage3_support() {
    python -c "import sys; exit(0 if sys.version_info >= (3, 13) else 1)" 2>/dev/null
    return $?
}

# Helper function: Get CUDA architecture list for compilation
# Usage: cuda_arch=$(get_cuda_arch_list SAGE_VERSION)
get_cuda_arch_list() {
    local sage_version="$1"
    if [[ "$sage_version" == "3" ]]; then
        echo "12.0"  # Blackwell
    else
        echo "8.0;8.9"  # Ampere/Ada
    fi
}

#########################################################
# End of launcher-common.sh
#########################################################
