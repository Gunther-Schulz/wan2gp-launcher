#!/bin/bash
#########################################################
# ComfyUI - Conda Environment Runner
# Activates conda environment and runs ComfyUI with
# shared model paths from wan2gp_content/ and models/
#########################################################

#########################################################
# Configuration Loading
#########################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared library
if [[ -f "${SCRIPT_DIR}/launcher-common.sh" ]]; then
    source "${SCRIPT_DIR}/launcher-common.sh"
else
    echo "ERROR: launcher-common.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

# Load user config
CONFIG_FILE="${SCRIPT_DIR}/comfyui-config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Set defaults for any missing config values
set_default_comfyui_config() {
    [[ -z "$CONDA_EXE" ]] && CONDA_EXE="/opt/miniconda3/bin/conda"
    [[ -z "$AUTO_GIT_UPDATE" ]] && AUTO_GIT_UPDATE=true
    [[ -z "$COMFYUI_PORT" ]] && COMFYUI_PORT="8188"
    [[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR=""
    [[ -z "$TEMP_DIR" ]] && TEMP_DIR=""
    [[ -z "$INPUT_DIR" ]] && INPUT_DIR=""
    [[ -z "$TEMP_CACHE_DIR" ]] && TEMP_CACHE_DIR=""
    [[ -z "$DEFAULT_SAGE_VERSION" ]] && DEFAULT_SAGE_VERSION="auto"
    [[ -z "$COMFYUI_REPO_URL" ]] && COMFYUI_REPO_URL="https://github.com/comfyanonymous/ComfyUI.git"
    [[ -z "$COMFYUI_REPO_BRANCH" ]] && COMFYUI_REPO_BRANCH=""
    [[ -z "$DISABLE_ERROR_REPORTING" ]] && DISABLE_ERROR_REPORTING=true
    [[ -z "$CONDA_ENV_NAME" ]] && CONDA_ENV_NAME="comfyui"
    [[ -z "$CONDA_ENV_FILE" ]] && CONDA_ENV_FILE="environment-comfyui.yml"
}
set_default_comfyui_config

COMFYUI_DIR="${SCRIPT_DIR}/ComfyUI"
ENV_NAME="$CONDA_ENV_NAME"
SAGE_VERSION="$DEFAULT_SAGE_VERSION"

#########################################################
# CLI Flag Parsing
#########################################################

REBUILD_ENV=false
NO_GIT_UPDATE=false

show_help() {
    printf "%s\n" "${delimiter}"
    printf "${GREEN}ComfyUI Launcher - Help${NC}\n"
    printf "%s\n" "${delimiter}"
    printf "\nUsage: %s [OPTIONS] [-- COMFYUI_ARGS]\n\n" "$0"
    printf "Options:\n"
    printf "  --rebuild-env       Remove and rebuild conda environment\n"
    printf "  --no-git-update     Skip git pull on this launch\n"
    printf "  --sage2             Use SageAttention 2.2.0\n"
    printf "  --sage3             Use SageAttention3 (Blackwell)\n"
    printf "  --port PORT         Set server port (default: %s)\n" "$COMFYUI_PORT"
    printf "  --help, -h          Show this help message\n"
    printf "\nAny arguments after -- are passed directly to ComfyUI.\n"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild-env) REBUILD_ENV=true; shift ;;
        --no-git-update) NO_GIT_UPDATE=true; shift ;;
        --sage2) SAGE_VERSION="2"; shift ;;
        --sage3) SAGE_VERSION="3"; shift ;;
        --port) COMFYUI_PORT="$2"; shift 2 ;;
        --help|-h) show_help ;;
        --) shift; break ;;
        *) break ;;
    esac
done

#########################################################
# Banner
#########################################################

printf "\n%s\n" "${delimiter}"
printf "${GREEN}ComfyUI Launcher${NC}\n"
printf "%s\n" "${delimiter}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    printf "${YELLOW}No comfyui-config.sh found - using defaults${NC}\n"
    printf "${BLUE}Copy comfyui-config.sh.sample to comfyui-config.sh to customize${NC}\n"
fi

#########################################################
# Validate Configured Paths (early — before any setup)
#########################################################

validate_comfyui_paths() {
    local validation_failed=false

    # Validate TEMP_CACHE_DIR if configured
    if [[ -n "$TEMP_CACHE_DIR" ]]; then
        if ! validate_temp_directory "$TEMP_CACHE_DIR"; then
            validation_failed=true
        fi
    fi

    # Validate OUTPUT_DIR if configured
    if [[ -n "$OUTPUT_DIR" ]]; then
        printf "${BLUE}Checking output directory: ${OUTPUT_DIR}${NC}\n"
        if [[ ! -d "$OUTPUT_DIR" ]]; then
            mkdir -p "$OUTPUT_DIR" 2>/dev/null
            if [[ ! -d "$OUTPUT_DIR" ]]; then
                printf "${RED}ERROR: Cannot create output directory: ${OUTPUT_DIR}${NC}\n"
                printf "${YELLOW}If using external drive, ensure it is mounted${NC}\n"
                validation_failed=true
            else
                printf "${GREEN}✓ Output directory created: ${OUTPUT_DIR}${NC}\n"
            fi
        fi
        if [[ -d "$OUTPUT_DIR" ]] && [[ ! -w "$OUTPUT_DIR" ]]; then
            printf "${RED}ERROR: Output directory is not writable: ${OUTPUT_DIR}${NC}\n"
            validation_failed=true
        elif [[ -d "$OUTPUT_DIR" ]]; then
            printf "${GREEN}✓ Output directory OK${NC}\n"
        fi
    fi

    # Validate TEMP_DIR if configured
    if [[ -n "$TEMP_DIR" ]]; then
        printf "${BLUE}Checking temp directory: ${TEMP_DIR}${NC}\n"
        if [[ ! -d "$TEMP_DIR" ]]; then
            mkdir -p "$TEMP_DIR" 2>/dev/null
            if [[ ! -d "$TEMP_DIR" ]]; then
                printf "${RED}ERROR: Cannot create temp directory: ${TEMP_DIR}${NC}\n"
                printf "${YELLOW}If using external drive, ensure it is mounted${NC}\n"
                validation_failed=true
            else
                printf "${GREEN}✓ Temp directory created: ${TEMP_DIR}${NC}\n"
            fi
        fi
        if [[ -d "$TEMP_DIR" ]] && [[ ! -w "$TEMP_DIR" ]]; then
            printf "${RED}ERROR: Temp directory is not writable: ${TEMP_DIR}${NC}\n"
            validation_failed=true
        elif [[ -d "$TEMP_DIR" ]]; then
            printf "${GREEN}✓ Temp directory OK${NC}\n"
        fi
    fi

    if [[ "$validation_failed" == "true" ]]; then
        printf "\n${RED}Path validation failed — cannot start${NC}\n"
        printf "${YELLOW}Please fix the issues above and try again${NC}\n"
        exit 1
    fi
}

if [[ -n "$OUTPUT_DIR" ]] || [[ -n "$TEMP_DIR" ]] || [[ -n "$TEMP_CACHE_DIR" ]]; then
    printf "\n${BLUE}Validating configured paths...${NC}\n"
    validate_comfyui_paths
fi

#########################################################
# Clone ComfyUI Repository
#########################################################

if [[ ! -d "$COMFYUI_DIR" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Cloning ComfyUI repository...${NC}\n"
    printf "%s\n" "${delimiter}"

    clone_args=("$COMFYUI_REPO_URL" "$COMFYUI_DIR")
    if [[ -n "$COMFYUI_REPO_BRANCH" ]]; then
        clone_args=("-b" "$COMFYUI_REPO_BRANCH" "${clone_args[@]}")
    fi

    git clone "${clone_args[@]}"
    if [[ $? -ne 0 ]]; then
        printf "${RED}ERROR: Failed to clone ComfyUI${NC}\n"
        exit 1
    fi
    printf "${GREEN}ComfyUI cloned successfully${NC}\n"
fi

#########################################################
# Conda Environment Management
#########################################################

detect_conda "comfyui-config.sh"

# Handle --rebuild-env
if [[ "$REBUILD_ENV" == "true" ]]; then
    printf "\n${YELLOW}Rebuilding conda environment '${ENV_NAME}'...${NC}\n"
    printf "${RED}This will remove the existing environment and create a fresh one.${NC}\n"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "${CONDA_EXE}" env remove -n "${ENV_NAME}" -y 2>/dev/null
        printf "${GREEN}Environment removed${NC}\n"
    else
        printf "${YELLOW}Rebuild cancelled${NC}\n"
        REBUILD_ENV=false
    fi
fi

# Create environment if it doesn't exist
if ! "${CONDA_EXE}" env list 2>/dev/null | grep -q "^${ENV_NAME} "; then
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Creating conda environment '${ENV_NAME}'...${NC}\n"
    printf "%s\n" "${delimiter}"

    if [[ ! -f "${SCRIPT_DIR}/${CONDA_ENV_FILE}" ]]; then
        printf "${RED}ERROR: ${CONDA_ENV_FILE} not found in ${SCRIPT_DIR}${NC}\n"
        exit 1
    fi

    "${CONDA_EXE}" env create -f "${SCRIPT_DIR}/${CONDA_ENV_FILE}"
    if [[ $? -ne 0 ]]; then
        printf "${RED}ERROR: Failed to create conda environment${NC}\n"
        exit 1
    fi

    # Activate and install pip packages
    eval "$("${CONDA_EXE}" shell.bash hook)"
    conda activate "${ENV_NAME}"

    printf "\n${GREEN}Installing ComfyUI pip packages...${NC}\n"
    if [[ -f "${COMFYUI_DIR}/requirements.txt" ]]; then
        pip install -r "${COMFYUI_DIR}/requirements.txt"
        if [[ $? -ne 0 ]]; then
            printf "${RED}ERROR: Failed to install pip packages${NC}\n"
            exit 1
        fi
    else
        printf "${RED}ERROR: requirements.txt not found in ${COMFYUI_DIR}${NC}\n"
        exit 1
    fi

    # Install SageAttention
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Installing SageAttention...${NC}\n"
    printf "%s\n" "${delimiter}"

    PYTORCH_CHECK=$(python -c "import torch; print(torch.__version__)" 2>/dev/null)
    if [[ -z "$PYTORCH_CHECK" ]]; then
        printf "${RED}ERROR: PyTorch not found after pip install${NC}\n"
        printf "${YELLOW}Skipping SageAttention installation${NC}\n"
    elif [[ "$DEFAULT_SAGE_VERSION" == "none" ]]; then
        printf "${BLUE}SageAttention disabled (DEFAULT_SAGE_VERSION=\"none\")${NC}\n"
    elif ! command -v nvcc &> /dev/null; then
        printf "${YELLOW}Warning: NVCC not found. SageAttention requires CUDA for compilation.${NC}\n"
        printf "${YELLOW}Skipping SageAttention installation.${NC}\n"
    else
        printf "${GREEN}PyTorch ${PYTORCH_CHECK} detected${NC}\n"

        # Resolve "auto" sage version
        if [[ "$SAGE_VERSION" == "auto" ]]; then
            detect_gpu
            SAGE_VERSION=$(get_recommended_sage_version)
            printf "${BLUE}Auto-detected SageAttention version: ${SAGE_VERSION}${NC}\n"
        fi

        export CUDA_HOME="${CONDA_PREFIX}"
        printf "${BLUE}CUDA_HOME: ${CUDA_HOME}${NC}\n"

        if [[ "$SAGE_VERSION" == "3" ]]; then
            if ! check_python_sage3_support; then
                printf "${YELLOW}Python <3.13 detected, falling back to SageAttention 2.2.0${NC}\n"
                SAGE_VERSION="2"
            else
                printf "${BLUE}Installing SageAttention3 (Blackwell optimized)...${NC}\n"
            fi
        fi

        if [[ "$SAGE_VERSION" == "3" ]]; then
            install_sage_from_source "$COMFYUI_DIR" "/tmp/sageattention_comfyui_initial.log" "3" "simple"
        else
            printf "${BLUE}Installing SageAttention 2.2.0...${NC}\n"
            install_sage_from_source "$COMFYUI_DIR" "/tmp/sageattention_comfyui_initial.log" "2" "auto"
        fi
    fi

    printf "\n${GREEN}Environment setup complete!${NC}\n"
fi

#########################################################
# Activate Environment
#########################################################

printf "\n%s\n" "${delimiter}"
printf "${GREEN}Activating conda environment '${ENV_NAME}'...${NC}\n"
printf "%s\n" "${delimiter}"

activate_conda_env

# Print environment info
PYTHON_VER=$(python --version 2>&1)
PYTORCH_VER=$(python -c "import torch; print(torch.__version__)" 2>/dev/null || echo "not found")
printf "${BLUE}Python: ${PYTHON_VER}${NC}\n"
printf "${BLUE}PyTorch: ${PYTORCH_VER}${NC}\n"

#########################################################
# Git Update
#########################################################

if [[ "$AUTO_GIT_UPDATE" == "true" && "$NO_GIT_UPDATE" != "true" ]]; then
    printf "\n${BLUE}Checking for ComfyUI updates...${NC}\n"
    cd "${COMFYUI_DIR}"
    git_output=$(git pull --ff-only 2>&1)
    if [[ $? -eq 0 ]]; then
        if echo "$git_output" | grep -q "Already up to date"; then
            printf "${GREEN}ComfyUI is up to date${NC}\n"
        else
            printf "${GREEN}ComfyUI updated:${NC}\n"
            echo "$git_output"
        fi
    else
        printf "${YELLOW}Warning: git pull failed (local changes?)${NC}\n"
        printf "${YELLOW}%s${NC}\n" "$git_output"
    fi
    cd "${SCRIPT_DIR}"
fi

#########################################################
# Custom Nodes — Install & Update
#########################################################

CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"

# Required custom nodes: name -> git URL
declare -A REQUIRED_NODES=(
    [ComfyUI-LTXVideo]="https://github.com/Lightricks/ComfyUI-LTXVideo.git"
    [ComfyUI-VideoHelperSuite]="https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    [ComfyUI-KJNodes]="https://github.com/kijai/ComfyUI-KJNodes.git"
    [rgthree-comfy]="https://github.com/rgthree/rgthree-comfy.git"
    [cg-sigmas]="https://github.com/chrisgoringe/cg-sigmas.git"
    [ComfyUI-Extra-Samplers]="https://github.com/Clybius/ComfyUI-Extra-Samplers.git"
    [comfyui-various]="https://github.com/jamesWalker55/comfyui-various.git"
    [ComfyMath]="https://github.com/evanspearman/ComfyMath.git"
    [RES4LYF]="https://github.com/ClownsharkBatwing/RES4LYF.git"
)

printf "\n%s\n" "${delimiter}"
printf "${GREEN}Checking custom nodes...${NC}\n"
printf "%s\n" "${delimiter}"

nodes_changed=false
for node_name in "${!REQUIRED_NODES[@]}"; do
    node_dir="${CUSTOM_NODES_DIR}/${node_name}"
    node_url="${REQUIRED_NODES[$node_name]}"

    if [[ ! -d "$node_dir" ]]; then
        printf "${BLUE}Installing ${node_name}...${NC}\n"
        git clone "$node_url" "$node_dir" 2>&1 | tail -1
        nodes_changed=true
    elif [[ "$AUTO_GIT_UPDATE" == "true" && "$NO_GIT_UPDATE" != "true" ]]; then
        cd "$node_dir"
        update_output=$(git pull --ff-only 2>&1)
        if echo "$update_output" | grep -q "Already up to date"; then
            printf "${GREEN}  ${node_name}: up to date${NC}\n"
        else
            printf "${GREEN}  ${node_name}: updated${NC}\n"
            nodes_changed=true
        fi
        cd "${SCRIPT_DIR}"
    else
        printf "${GREEN}  ${node_name}: installed${NC}\n"
    fi
done

if [[ "$nodes_changed" == "true" ]]; then
    printf "${BLUE}Installing custom node dependencies...${NC}\n"
    for req_file in "${CUSTOM_NODES_DIR}"/*/requirements.txt; do
        [[ -f "$req_file" ]] && pip install -r "$req_file" -q 2>&1 | grep -v "already satisfied" | tail -3
    done
    # Extra deps not declared in any requirements.txt
    pip install soundfile -q 2>&1 | grep -v "already satisfied"
    printf "${GREEN}Custom nodes updated${NC}\n"
fi

#########################################################
# Generate extra_model_paths.yaml
#########################################################

generate_extra_model_paths() {
    local yaml_file="${SCRIPT_DIR}/comfyui_extra_model_paths.yaml"
    local content_dir="${SCRIPT_DIR}/wan2gp_content"
    local models_dir="${SCRIPT_DIR}/models"

    printf "${BLUE}Generating model paths configuration...${NC}\n"

    cat > "$yaml_file" << 'HEADER'
# Auto-generated by run-comfyui-conda.sh
# Do not edit manually - regenerated on every launch

HEADER

    # wan2gp_content section
    if [[ -d "$content_dir" ]]; then
        {
            echo "wan2gp_content:"
            echo "  base_path: ${content_dir}"
            [[ -d "${content_dir}/ckpts" ]] && echo "  checkpoints: ckpts/"
            [[ -d "${content_dir}/ckpts" ]] && echo "  diffusion_models: ckpts/"
            [[ -d "${content_dir}/loras" ]] && echo "  loras: loras/"
            echo ""
        } >> "$yaml_file"
    fi

    # forge models section
    if [[ -d "$models_dir" ]]; then
        {
            echo "forge_models:"
            echo "  base_path: ${models_dir}"
            [[ -d "${models_dir}/Stable-diffusion" ]] && echo "  checkpoints: Stable-diffusion/"
            [[ -d "${models_dir}/VAE" ]] && echo "  vae: VAE/"
            [[ -d "${models_dir}/Lora" ]] && echo "  loras: Lora/"
            [[ -d "${models_dir}/ControlNet" ]] && echo "  controlnet: ControlNet/"
            [[ -d "${models_dir}/text_encoder" ]] && echo "  text_encoders: text_encoder/"
            [[ -d "${models_dir}/diffusers" ]] && echo "  diffusers: diffusers/"
            [[ -d "${models_dir}/hypernetworks" ]] && echo "  hypernetworks: hypernetworks/"
            [[ -d "${models_dir}/embeddings" ]] && echo "  embeddings: embeddings/"

            # upscale_models: combine ESRGAN and RealESRGAN if both exist
            local has_esrgan=false has_realesrgan=false
            [[ -d "${models_dir}/ESRGAN" ]] && has_esrgan=true
            [[ -d "${models_dir}/RealESRGAN" ]] && has_realesrgan=true

            if [[ "$has_esrgan" == "true" && "$has_realesrgan" == "true" ]]; then
                echo "  upscale_models: |"
                echo "    ESRGAN/"
                echo "    RealESRGAN/"
            elif [[ "$has_esrgan" == "true" ]]; then
                echo "  upscale_models: ESRGAN/"
            elif [[ "$has_realesrgan" == "true" ]]; then
                echo "  upscale_models: RealESRGAN/"
            fi
        } >> "$yaml_file"
    fi

    printf "${GREEN}Model paths written to ${yaml_file}${NC}\n"
}

generate_extra_model_paths

#########################################################
# Build Launch Arguments
#########################################################

LAUNCH_ARGS=""
LAUNCH_ARGS="$LAUNCH_ARGS --port $COMFYUI_PORT"
LAUNCH_ARGS="$LAUNCH_ARGS --extra-model-paths-config ${SCRIPT_DIR}/comfyui_extra_model_paths.yaml"

[[ -n "$OUTPUT_DIR" ]] && LAUNCH_ARGS="$LAUNCH_ARGS --output-directory $OUTPUT_DIR"
[[ -n "$TEMP_DIR" ]] && LAUNCH_ARGS="$LAUNCH_ARGS --temp-directory $TEMP_DIR"
[[ -n "$INPUT_DIR" ]] && LAUNCH_ARGS="$LAUNCH_ARGS --input-directory $INPUT_DIR"

# Resolve sage version for launch (may not have been resolved during env creation)
if [[ "$SAGE_VERSION" == "auto" ]]; then
    detect_gpu
    SAGE_VERSION=$(get_recommended_sage_version)
fi

if [[ "$SAGE_VERSION" != "none" ]]; then
    LAUNCH_ARGS="$LAUNCH_ARGS --use-sage-attention"
fi

# Disable telemetry if configured
if [[ "$DISABLE_ERROR_REPORTING" == "true" ]]; then
    export HF_HUB_DISABLE_TELEMETRY=1
    export DO_NOT_TRACK=1
fi

#########################################################
# Launch ComfyUI
#########################################################

printf "\n%s\n" "${delimiter}"
printf "${GREEN}Launching ComfyUI on port ${COMFYUI_PORT}...${NC}\n"
printf "%s\n" "${delimiter}"
printf "${BLUE}Arguments: ${LAUNCH_ARGS} $*${NC}\n"

# Remind about available workflows
if ls "${COMFYUI_DIR}"/user/default/workflows/*.json &>/dev/null; then
    printf "${BLUE}Workflows available in ComfyUI (use Open > Browse):${NC}\n"
    for wf in "${COMFYUI_DIR}"/user/default/workflows/*.json; do
        printf "  ${GREEN}$(basename "$wf")${NC}\n"
    done
fi
echo ""

cd "${COMFYUI_DIR}"
export CUDA_HOME="${CUDA_HOME:-${CONDA_PREFIX}}"

python -u main.py $LAUNCH_ARGS "$@"
