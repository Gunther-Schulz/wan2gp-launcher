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

# Pretty print delimiter (used by both launchers)
delimiter="################################################################"

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

# Helper function: Detect conda installation
# Sets CONDA_EXE to "conda" if found in PATH, or uses configured CONDA_EXE
# Exits with error if conda not found
# Usage: detect_conda [config_file_name]
#   config_file_name: Name of config file for error messages (e.g., "forge-config.sh")
detect_conda() {
    local config_file="${1:-config.sh}"
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Detecting conda installation...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # First, try to find conda in PATH
    if command -v conda &> /dev/null; then
        CONDA_EXE="conda"
        local CONDA_LOCATION=$(which conda)
        printf "${GREEN}Found conda in PATH: ${CONDA_LOCATION}${NC}\n"
    elif [[ -f "${CONDA_EXE}" ]]; then
        # Fall back to configured location
        printf "${GREEN}Using configured conda location: ${CONDA_EXE}${NC}\n"
    else
        # Neither PATH nor configured location worked
        printf "\n%s\n" "${delimiter}"
        printf "${RED}ERROR: conda not found${NC}\n"
        printf "${YELLOW}Tried:${NC}\n"
        printf "  1. conda command in PATH\n"
        printf "  2. Configured location: ${CONDA_EXE}\n"
        printf "\n${YELLOW}Solutions:${NC}\n"
        printf "  1. Install conda/miniconda/anaconda:\n"
        printf "     - Download from: https://docs.conda.io/en/latest/miniconda.html\n"
        printf "     - Or install via package manager (if available)\n"
        printf "  2. Ensure conda is in your PATH:\n"
        printf "     - Add conda to ~/.bashrc: export PATH=\"/path/to/conda/bin:\$PATH\"\n"
        printf "     - Or activate conda: source /path/to/conda/etc/profile.d/conda.sh\n"
        printf "  3. Update CONDA_EXE in ${config_file} to point to your conda installation\n"
        printf "  4. If using system conda: sudo pacman -S conda (Arch/CachyOS)\n"
        printf "%s\n" "${delimiter}"
        exit 1
    fi
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
# Also sets: GPU_COUNT, GPU_NAMES[], GPU_COMPUTE_CAPS[] for multi-GPU systems
# Usage: detect_gpu
detect_gpu() {
    GPU_VENDOR="unknown"
    GPU_NAME="unknown"
    GPU_COMPUTE_CAP=""
    SUPPORTS_SAGE3=false
    GPU_COUNT=0
    GPU_NAMES=()
    GPU_COMPUTE_CAPS=()
    
    # Try nvidia-smi for NVIDIA GPUs
    if command -v nvidia-smi &> /dev/null; then
        GPU_VENDOR="nvidia"
        
        # Get all GPU names
        mapfile -t GPU_NAMES < <(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null)
        GPU_COUNT=${#GPU_NAMES[@]}
        
        # Get all compute capabilities
        mapfile -t GPU_COMPUTE_CAPS < <(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | tr -d ' ')
        
        # Use first GPU for primary detection (backward compatibility)
        if [[ $GPU_COUNT -gt 0 ]]; then
            GPU_NAME="${GPU_NAMES[0]}"
            
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
            # Try to get compute cap from nvidia-smi if name detection failed
            elif [[ -n "${GPU_COMPUTE_CAPS[0]}" ]]; then
                GPU_COMPUTE_CAP="${GPU_COMPUTE_CAPS[0]}"
                # Check if any GPU supports Sage3 (Blackwell = 12.0+)
                for cap in "${GPU_COMPUTE_CAPS[@]}"; do
                    if command -v bc &> /dev/null && [[ $(echo "$cap >= 12.0" | bc 2>/dev/null || echo "0") == "1" ]]; then
                        SUPPORTS_SAGE3=true
                        break
                    fi
                done
            fi
        fi
    # Try lspci for AMD/Intel GPUs
    elif command -v lspci &> /dev/null; then
        local gpu_info=$(lspci | grep -i "vga\|3d\|display" | head -1)
        if echo "$gpu_info" | grep -qi "amd\|radeon"; then
            GPU_VENDOR="amd"
            GPU_NAME=$(echo "$gpu_info" | sed 's/.*: //')
            GPU_COUNT=1
            GPU_NAMES=("$GPU_NAME")
        elif echo "$gpu_info" | grep -qi "intel"; then
            GPU_VENDOR="intel"
            GPU_NAME=$(echo "$gpu_info" | sed 's/.*: //')
            GPU_COUNT=1
            GPU_NAMES=("$GPU_NAME")
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
# Usage: cuda_arch=$(get_cuda_arch_list SAGE_VERSION [auto])
# Parameters:
#   sage_version: "2" or "3"
#   auto: if "auto", attempts to detect GPU and return optimal arch list
# Returns: CUDA arch list string like "8.0;8.9" or "12.0"
get_cuda_arch_list() {
    local sage_version="$1"
    local auto_detect="${2:-}"
    
    # Auto-detection mode (optional, for advanced users)
    if [[ "$auto_detect" == "auto" ]] && command -v nvidia-smi &> /dev/null; then
        local DETECTED_ARCHS=()
        while IFS= read -r compute_cap; do
            compute_cap=$(echo "$compute_cap" | tr -d ' ')
            if [[ -n "$compute_cap" ]]; then
                case "$compute_cap" in
                    7.0) DETECTED_ARCHS+=("7.0") ;;
                    7.5) DETECTED_ARCHS+=("7.5") ;;
                    8.0|8.6) DETECTED_ARCHS+=("8.0") ;;
                    8.9) DETECTED_ARCHS+=("8.9") ;;
                    9.0) DETECTED_ARCHS+=("9.0") ;;
                    10.*) DETECTED_ARCHS+=("10.0") ;;
                    12.*) DETECTED_ARCHS+=("12.0") ;;
                esac
            fi
        done < <(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | sort -u)
        
        if [[ ${#DETECTED_ARCHS[@]} -gt 0 ]]; then
            local UNIQUE_ARCHS=($(printf '%s\n' "${DETECTED_ARCHS[@]}" | sort -u))
            local AUTO_ARCH_LIST=$(IFS=';'; echo "${UNIQUE_ARCHS[*]}")
            echo "$AUTO_ARCH_LIST"
            return 0
        fi
    fi
    
    # Default/fallback mode (always works)
    if [[ "$sage_version" == "3" ]]; then
        echo "12.0"  # Blackwell
    else
        echo "8.0;8.9"  # Ampere/Ada (RTX 30xx/40xx)
    fi
}

# Helper function: Initialize content directory structure
# Usage: init_content_directories "content_root" "project_name" "lora_subdirs_array"
# Example: init_content_directories "/path/to/content" "Wan2GP" "wan wan_i2v flux"
init_content_directories() {
    local content_root="$1"
    local project_name="$2"
    shift 2
    local lora_subdirs=("$@")
    
    # Check if already exists
    if [[ -d "$content_root" ]]; then
        return 0
    fi
    
    printf "${GREEN}Initializing ${project_name} content directory structure...${NC}\n"
    printf "${BLUE}Creating directories for models, loras, and configurations...${NC}\n"
    
    # Create base directories
    mkdir -p "${content_root}/ckpts"
    mkdir -p "${content_root}/finetunes"
    mkdir -p "${content_root}/loras"
    
    # Create loras subdirectories
    for subdir in "${lora_subdirs[@]}"; do
        mkdir -p "${content_root}/loras/${subdir}"
    done
    
    # Create README
    cat > "${content_root}/README.md" << EOF
# ${project_name} Content Directory

This directory contains all your custom models, LoRAs, and configurations.

## Directory Layout

- \`ckpts/\` - Model checkpoints (safetensors files)
  - Place your downloaded or custom models here
  - Auto-downloaded models will be saved here

- \`finetunes/\` - Configuration files (JSON)
  - Custom training configurations
  - Model fine-tuning presets

- \`loras/\` - LoRA files organized by type
$(for subdir in "${lora_subdirs[@]}"; do echo "  - \`${subdir}/\` - ${subdir} LoRAs"; done)

## How It Works

The launcher creates directory symlinks from \`${project_name}/\` to this location.
This keeps all your custom content in one organized location while appearing
natively in the application directory.

Benefits:
- All custom content in one place
- Survives git pulls and updates
- Easy to backup or share
- No risk of losing files during updates
EOF
    
    printf "${GREEN}✓ Created content directory structure${NC}\n"
    printf "${BLUE}  Location: ${content_root}${NC}\n"
    printf "${BLUE}  Base directories: ckpts, finetunes, loras${NC}\n"
    printf "${BLUE}  LoRA subdirectories: ${#lora_subdirs[@]} types${NC}\n"
}

# Helper function: Link entire directory with symlink
# Usage: link_content_directory "source_dir" "target_path" "display_name"
# Returns: 0 on success, 1 on error
# This creates a symlink at target_path pointing to source_dir
link_content_directory() {
    local source_dir="$1"
    local target_path="$2"
    local display_name="$3"
    
    # Check if source directory exists
    if [[ ! -d "$source_dir" ]]; then
        printf "${YELLOW}Source directory not found: ${source_dir}${NC}\n"
        return 1
    fi
    
    # Get absolute path for source
    local source_abs=$(readlink -f "$source_dir")
    
    # Check if target already exists and is correct symlink
    if [[ -L "$target_path" ]]; then
        local current_target=$(readlink -f "$target_path" 2>/dev/null || echo "")
        if [[ "$current_target" == "$source_abs" ]]; then
            printf "${GREEN}✓ ${display_name} already linked correctly${NC}\n"
            return 0
        else
            printf "${YELLOW}Updating ${display_name} symlink...${NC}\n"
            rm -f "$target_path"
        fi
    elif [[ -e "$target_path" ]]; then
        # Target exists but is not a symlink (could be directory or file)
        printf "${YELLOW}Removing existing ${display_name} at target location...${NC}\n"
        rm -rf "$target_path"
    fi
    
    # Ensure parent directory exists
    local parent_dir=$(dirname "$target_path")
    mkdir -p "$parent_dir"
    
    # Create the symlink
    ln -sfn "$source_abs" "$target_path"
    
    if [[ $? -eq 0 ]]; then
        printf "${GREEN}✓ ${display_name} linked successfully${NC}\n"
        return 0
    else
        printf "${RED}✗ Failed to link ${display_name}${NC}\n"
        return 1
    fi
}

# Helper function: Prepare TCMalloc for better memory performance
# Usage: prepare_tcmalloc ENV_NAME CONDA_EXE ENABLE_TCMALLOC TCMALLOC_GLIBC_THRESHOLD
prepare_tcmalloc() {
    local env_name="$1"
    local conda_exe="$2"
    local enable_tcmalloc="$3"
    local glibc_threshold="${4:-2.34}"
    
    if [[ "${OSTYPE}" != "linux"* ]] || [[ -n "${NO_TCMALLOC}" ]] || [[ -n "${LD_PRELOAD}" ]]; then
        return 0
    fi
    
    # Check if disabled
    if [[ "${enable_tcmalloc}" == "false" ]]; then
        printf "${YELLOW}TCMalloc disabled${NC}\n"
        return 0
    fi
    
    # Activate conda environment if using conda
    if [[ -n "${conda_exe}" ]]; then
        printf "${GREEN}Enabling TCMalloc with conda environment integration...${NC}\n"
        eval "$("${conda_exe}" shell.bash hook)" 2>/dev/null
        conda activate "${env_name}" 2>/dev/null || {
            printf "${RED}Warning: Could not activate conda environment for TCMalloc${NC}\n"
            return 1
        }
    fi
    
    # Detect glibc version
    LIBC_VER=$(ldd --version 2>/dev/null | awk 'NR==1 {print $NF}' | grep -oP '\d+\.\d+')
    echo "glibc version is $LIBC_VER"
    libc_vernum=$(expr $LIBC_VER 2>/dev/null || echo "0")
    libc_v234="$glibc_threshold"
    TCMALLOC_LIBS=("libtcmalloc(_minimal|)\.so\.\d" "libtcmalloc\.so\.\d")

    for lib in "${TCMALLOC_LIBS[@]}"; do
        TCMALLOC="$(PATH=/sbin:/usr/sbin:$PATH ldconfig -p 2>/dev/null | grep -P $lib | head -n 1)"
        TC_INFO=(${TCMALLOC//=>/})
        if [[ -n "${TC_INFO}" ]]; then
            echo "Check TCMalloc: ${TC_INFO}"
            # Check for library compatibility
            if ldd ${TC_INFO[2]} 2>/dev/null | grep -q 'GLIBCXX_3.4.30'; then
                printf "${YELLOW}TCMalloc requires GLIBCXX_3.4.30 - skipping to avoid conflicts${NC}\n"
                break
            fi
            
            if command -v bc &> /dev/null && [ $(echo "$libc_vernum < $libc_v234" | bc) -eq 1 ]; then
                if ldd ${TC_INFO[2]} 2>/dev/null | grep -q 'libpthread'; then
                    echo "$TC_INFO is linked with libpthread, execute LD_PRELOAD=${TC_INFO[2]}"
                    export LD_PRELOAD="${TC_INFO[2]}"
                    break
                fi
            else
                echo "$TC_INFO is linked with libc.so, execute LD_PRELOAD=${TC_INFO[2]}"
                export LD_PRELOAD="${TC_INFO[2]}"
                break
            fi
        fi
    done
    
    if [[ -z "${LD_PRELOAD}" ]]; then
        printf "${YELLOW}Cannot locate compatible TCMalloc (improves CPU memory usage)${NC}\n"
    fi
}

# Helper function: Clean up cache directories
# Usage: cleanup_cache PROJECT_DIR TEMP_CACHE_DIR CACHE_SIZE_THRESHOLD AUTO_CACHE_CLEANUP FORCE_CACHE_CLEANUP
cleanup_cache() {
    local project_dir="$1"
    local temp_cache_dir="$2"
    local cache_size_threshold="${3:-100}"
    local auto_cache_cleanup="${4:-false}"
    local force_cache_cleanup="${5:-false}"
    
    if [[ "$auto_cache_cleanup" != "true" ]] && [[ "$force_cache_cleanup" != "true" ]]; then
        printf "${BLUE}Automatic cache cleanup disabled${NC}\n"
        return 0
    fi
    
    printf "${BLUE}Cleaning up cache directories...${NC}\n"
    
    # Clean up system /tmp/gradio cache
    if [[ -d "/tmp/gradio" ]]; then
        printf "${YELLOW}Removing system Gradio cache: /tmp/gradio${NC}\n"
        rm -rf "/tmp/gradio" 2>/dev/null || printf "${YELLOW}Warning: Could not remove /tmp/gradio${NC}\n"
    fi
    
    # Clean up custom temp directory if configured
    if [[ -n "$temp_cache_dir" ]] && [[ -d "$temp_cache_dir" ]]; then
        CACHE_SIZE=$(du -sm "$temp_cache_dir" 2>/dev/null | cut -f1 || echo "0")
        if [[ $CACHE_SIZE -gt $cache_size_threshold ]] || [[ "$force_cache_cleanup" == "true" ]]; then
            if [[ "$force_cache_cleanup" == "true" ]]; then
                printf "${YELLOW}Force cleaning custom temp cache (${CACHE_SIZE}MB)...${NC}\n"
            else
                printf "${YELLOW}Custom temp cache is ${CACHE_SIZE}MB (threshold: ${cache_size_threshold}MB), cleaning up...${NC}\n"
            fi
            rm -rf "${temp_cache_dir}"/* 2>/dev/null || printf "${YELLOW}Warning: Could not clean custom cache${NC}\n"
        else
            printf "${GREEN}Custom temp cache size: ${CACHE_SIZE}MB (threshold: ${cache_size_threshold}MB, keeping)${NC}\n"
        fi
    fi
    
    # Clean up Python cache
    if [[ -n "$project_dir" ]] && [[ -d "$project_dir" ]]; then
        if [[ "$auto_cache_cleanup" == "true" ]] || [[ "$force_cache_cleanup" == "true" ]]; then
            if [[ -d "${project_dir}/__pycache__" ]]; then
                printf "${YELLOW}Cleaning Python cache...${NC}\n"
                find "${project_dir}" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
                find "${project_dir}" -name "*.pyc" -delete 2>/dev/null || true
            fi
        fi
    fi
    
    printf "${GREEN}Cache cleanup completed${NC}\n"
}

# Helper function: Verify package versions match requirements.txt
# Usage: verify_package_versions REQUIREMENTS_FILE ENV_NAME CONDA_EXE AUTO_CHECK_PACKAGES AUTO_FIX_PACKAGE_MISMATCHES
# Returns: 0 if all OK, 1 if errors
verify_package_versions() {
    local requirements_file="$1"
    local env_name="$2"
    local conda_exe="$3"
    local auto_check="${4:-true}"
    local auto_fix="${5:-true}"
    
    if [[ "$auto_check" != "true" ]]; then
        return 0
    fi
    
    if [[ ! -f "$requirements_file" ]]; then
        printf "${YELLOW}Warning: requirements.txt not found, skipping version check${NC}\n"
        return 0
    fi
    
    # Activate conda environment for python access
    eval "$("${conda_exe}" shell.bash hook)" 2>/dev/null
    conda activate "${env_name}" 2>/dev/null
    
    # Use Python to check for version mismatches
    local check_result=$(python -c "
import sys
import re
from importlib.metadata import version, PackageNotFoundError

def parse_requirement(line):
    line = line.strip()
    if not line or line.startswith('#'):
        return None, None
    line = line.split('#')[0].strip()
    match = re.match(r'^([a-zA-Z0-9_-]+)(==|>=)([0-9.]+)', line)
    if match:
        return match.group(1), (match.group(2), match.group(3))
    return None, None

def normalize_version(ver_str):
    base_ver = ver_str.split('+')[0]
    match = re.match(r'^(\d+(?:\.\d+)*)', base_ver)
    if match:
        return match.group(1)
    return base_ver

def get_package_version(pkg_name):
    for name_variant in [pkg_name, pkg_name.replace('-', '_'), pkg_name.replace('_', '-'), pkg_name.lower()]:
        try:
            return version(name_variant)
        except PackageNotFoundError:
            pass
    raise PackageNotFoundError(pkg_name)

mismatches = []
requirements = {}

try:
    with open('${requirements_file}', 'r') as f:
        for line in f:
            pkg_name, version_spec = parse_requirement(line)
            if pkg_name and version_spec:
                requirements[pkg_name] = version_spec
except Exception as e:
    print(f'ERROR_READING_FILE:{e}')
    sys.exit(1)

for pkg_name, (operator, required_ver) in requirements.items():
    try:
        installed_ver_raw = get_package_version(pkg_name)
        installed_ver = normalize_version(installed_ver_raw)
        
        try:
            inst_parts = [int(x) for x in installed_ver.split('.')]
            req_parts = [int(x) for x in required_ver.split('.')]
            max_len = max(len(inst_parts), len(req_parts))
            inst_parts += [0] * (max_len - len(inst_parts))
            req_parts += [0] * (max_len - len(req_parts))
            
            if operator == '==':
                if inst_parts != req_parts:
                    mismatches.append(f'{pkg_name}|{installed_ver}|{required_ver}|exact')
            elif operator == '>=':
                if inst_parts < req_parts:
                    mismatches.append(f'{pkg_name}|{installed_ver}|{required_ver}|minimum')
        except (ValueError, AttributeError):
            pass
    except PackageNotFoundError:
        pass

if mismatches:
    print('MISMATCHES_FOUND')
    for m in mismatches:
        print(m)
else:
    print('ALL_OK')
" 2>&1)
    
    if [[ "$check_result" == *"ERROR_READING_FILE"* ]]; then
        printf "${RED}Error reading requirements.txt${NC}\n"
        return 1
    elif [[ "$check_result" == "ALL_OK" ]]; then
        printf "${GREEN}✓ All package versions match requirements.txt${NC}\n"
        return 0
    elif [[ "$check_result" == *"MISMATCHES_FOUND"* ]]; then
        printf "${YELLOW}Package version mismatches detected:${NC}\n"
        
        local has_critical=false
        local mismatch_count=0
        while IFS='|' read -r pkg installed required type; do
            if [[ "$pkg" == "MISMATCHES_FOUND" ]]; then
                continue
            fi
            
            ((mismatch_count++))
            
            case "$type" in
                exact)
                    printf "${YELLOW}  • ${pkg}: installed=${installed}, required=${required} (exact match needed)${NC}\n"
                    has_critical=true
                    ;;
                minimum)
                    printf "${YELLOW}  • ${pkg}: installed=${installed}, required>=${required} (too old)${NC}\n"
                    has_critical=true
                    ;;
            esac
        done <<< "$check_result"
        
        printf "${BLUE}Total mismatches found: ${mismatch_count}${NC}\n"
        
        if [[ "$has_critical" == "true" ]]; then
            if [[ "$auto_fix" == "true" ]]; then
                printf "\n${GREEN}Auto-fixing package mismatches...${NC}\n"
                pip install -r "$requirements_file"
                
                if [[ $? -eq 0 ]]; then
                    printf "${GREEN}✓ Successfully updated packages to match requirements${NC}\n"
                    return 0
                else
                    printf "${RED}✗ Failed to update some packages${NC}\n"
                    return 1
                fi
            else
                printf "\n${YELLOW}Auto-fix is disabled${NC}\n"
                printf "${YELLOW}To fix, run: pip install -r requirements.txt${NC}\n"
                return 0
            fi
        fi
    fi
    
    return 0
}

# Helper function: Validate temp directory
# Usage: validate_temp_directory TEMP_CACHE_DIR
# Returns: 0 if valid or not configured, 1 if invalid
validate_temp_directory() {
    local temp_cache_dir="$1"
    
    if [[ -z "$temp_cache_dir" ]]; then
        printf "${BLUE}No custom temp directory configured - will use system default${NC}\n"
        return 0
    fi
    
    printf "${BLUE}Checking temp cache directory: ${temp_cache_dir}${NC}\n"
    
    if [[ ! -d "$temp_cache_dir" ]]; then
        printf "${RED}CRITICAL ERROR: Custom temp directory does not exist: ${temp_cache_dir}${NC}\n"
        printf "${YELLOW}Cannot proceed - temp directory is mandatory when configured.${NC}\n"
        printf "${YELLOW}Solutions:${NC}\n"
        printf "  1. Create the directory: mkdir -p \"${temp_cache_dir}\"${NC}\n"
        printf "  2. If using external/network drive, ensure it's mounted${NC}\n"
        printf "  3. Remove TEMP_CACHE_DIR from config to use system default${NC}\n"
        return 1
    elif [[ ! -w "$temp_cache_dir" ]]; then
        printf "${RED}CRITICAL ERROR: Custom temp directory is not writable: ${temp_cache_dir}${NC}\n"
        printf "${YELLOW}Cannot proceed - check permissions.${NC}\n"
        return 1
    else
        printf "${GREEN}✓ Temp cache directory exists and is writable${NC}\n"
        return 0
    fi
}

#########################################################
# SageAttention Installation Functions
#########################################################

# Helper function: Install SageAttention from source (unified for all launchers)
# Usage: install_sage_from_source PROJECT_DIR BUILD_LOG SAGE_VERSION [ARCH_MODE]
# Parameters:
#   PROJECT_DIR: Directory to return to after build (e.g., WAN2GP_DIR or WEBUI_DIR)
#   BUILD_LOG: Path to build log file
#   SAGE_VERSION: "2" or "3"
#   ARCH_MODE: "simple" (default) or "auto" - whether to auto-detect GPU arch
# Returns: 0 on success, 1 on failure
# Note: Based on wan2gp's working implementation
install_sage_from_source() {
    local project_dir="$1"
    local build_log="$2"
    local sage_version="$3"
    local arch_mode="${4:-simple}"
    
    local SAGE_DIR="/tmp/SageAttention_build_$$"  # Unique per-process
    
    # Clean up any existing build directory
    if [[ -d "$SAGE_DIR" ]]; then
        rm -rf "$SAGE_DIR"
    fi
    
    # Clone SageAttention repository
    printf "${BLUE}Cloning SageAttention repository...${NC}\n"
    git clone "$SAGE_REPO_URL" "$SAGE_DIR" 2>&1
    if [[ $? -ne 0 ]]; then
        printf "${RED}✗ Failed to clone SageAttention repository${NC}\n"
        printf "${YELLOW}Check your internet connection${NC}\n"
        return 1
    fi
    
    # Install build dependencies (required for compilation)
    printf "${BLUE}Installing build dependencies...${NC}\n"
    pip install ninja packaging wheel setuptools
    
    # Calculate optimal parallel compilation jobs
    local PARALLEL_JOBS=$(calculate_parallel_jobs)
    printf "${BLUE}Using ${PARALLEL_JOBS} parallel jobs for compilation (75%% of cores)${NC}\n"
    
    # Set parallel compilation environment variables
    set_parallel_build_env "$PARALLEL_JOBS"
    export CUDA_HOME="${CUDA_HOME:-${CONDA_PREFIX}}"
    export VERBOSE="1"
    
    # Navigate to appropriate directory and set architecture list
    if [[ "$sage_version" == "3" ]]; then
        cd "$SAGE_DIR/sageattention3_blackwell"
        export TORCH_CUDA_ARCH_LIST="12.0"  # Blackwell
        printf "${GREEN}Installing SageAttention3 (Blackwell optimized)${NC}\n"
        printf "${BLUE}Target architecture: Blackwell (sm_120)${NC}\n"
        uninstall_sageattention "3"
    else
        cd "$SAGE_DIR"
        export TORCH_CUDA_ARCH_LIST=$(get_cuda_arch_list "2" "$arch_mode")
        printf "${GREEN}Installing SageAttention 2.2.0 (Ampere/Ada)${NC}\n"
        printf "${BLUE}Target architectures: ${TORCH_CUDA_ARCH_LIST}${NC}\n"
        uninstall_sageattention "2"
    fi
    
    printf "${BLUE}Compiling SageAttention from source (this may take several minutes)...${NC}\n"
    printf "${BLUE}Using CUDA_HOME: ${CUDA_HOME}${NC}\n"
    printf "${BLUE}Build directory: ${PWD}${NC}\n"
    
    # Compile with setup.py
    python setup.py install 2>&1 | tee "$build_log"
    local result=$?
    
    # Return to project directory
    cd "$project_dir"
    
    # Check result
    if [[ $result -eq 0 ]]; then
        printf "${GREEN}✓ SageAttention installed successfully${NC}\n"
        printf "${GREEN}✓ Build log: ${build_log}${NC}\n"
        rm -rf "$SAGE_DIR"
        return 0
    else
        printf "${RED}✗ Failed to compile SageAttention${NC}\n"
        printf "${RED}Exit code: ${result}${NC}\n"
        printf "${YELLOW}Build log: ${build_log}${NC}\n"
        printf "${YELLOW}Build directory preserved: ${SAGE_DIR}${NC}\n"
        return 1
    fi
}

# Helper function: Check if Sage installation should be skipped
# Usage: if should_skip_sage_install; then skip; fi
# Checks: DISABLE_SAGE, SAGE_VERSION=="none", DEFAULT_SAGE_VERSION=="none"
should_skip_sage_install() {
    [[ "$DISABLE_SAGE" == "true" ]] || \
    [[ "$SAGE_VERSION" == "none" ]] || \
    [[ "$DEFAULT_SAGE_VERSION" == "none" ]]
}

# Helper function: Detect installed SageAttention version
# Returns: "NOT_INSTALLED", "sageattn3:VERSION", or "VERSION" (for v2)
# Usage: installed_version=$(detect_sage_version [check_sageattn3])
#   check_sageattn3: if "true", also checks for sageattn3 package (default: false)
detect_sage_version() {
    local check_sageattn3="${1:-false}"
    
    local installed_version=$(python -c "
try:
    import sageattention
    # Check if main function exists
    if hasattr(sageattention, 'sageattn'):
        # Try to get version from importlib.metadata
        try:
            from importlib.metadata import version
            print(version('sageattention'))
        except:
            # No version metadata, but it's installed
            print('2.2.0')  # Assume current version if we can import it
    else:
        print('NOT_INSTALLED')
except ImportError:
    if ${check_sageattn3}:
        # Also check for sageattn3 (SageAttention3)
        try:
            import sageattn3
            try:
                from importlib.metadata import version
                print('sageattn3:' + version('sageattn3'))
            except:
                print('sageattn3:1.0.0')  # Default version
        except ImportError:
            print('NOT_INSTALLED')
    else:
        print('NOT_INSTALLED')
" 2>/dev/null)
    
    echo "$installed_version"
}

#########################################################
# End of launcher-common.sh
#########################################################
