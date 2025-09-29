#!/bin/bash
#########################################################
# Stable Diffusion WebUI Forge - Conda Environment Runner
# This script activates the conda environment and runs the WebUI
# without trying to install dependencies itself
#
# Usage:
#   ./run-forge-conda.sh [options] [other webui args...]
#
# Options:
#   --models-dir PATH      Override the models directory location
#   --use-custom-dir, -c   Use preset custom models dir (from config)
#   --output-dir PATH      Override the output directory for generated images
#   --clean-cache          Force full cache cleanup on startup
#   --disable-tcmalloc     Disable TCMalloc (if you experience library conflicts)
#   --rebuild-env          Remove and rebuild the conda environment
#   --no-git-update        Skip git update for this run
#
# Examples:
#   ./run-forge-conda.sh                              # Use configured default models dir
#   ./run-forge-conda.sh -c                          # Use preset custom models dir (shorthand)
#   ./run-forge-conda.sh --use-custom-dir             # Use preset custom models dir (full)
#   ./run-forge-conda.sh --models-dir /path/to/models # Use specific models dir
#   ./run-forge-conda.sh --output-dir /path/to/output # Use specific output dir
#   ./run-forge-conda.sh --clean-cache                # Force cache cleanup
#########################################################

#########################################################
# Configuration Loading
#########################################################

# Get the directory where this script is located (needed for config file path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from external config file
CONFIG_FILE="${SCRIPT_DIR}/forge-config.sh"

# Set fallback defaults in case config file is missing or incomplete
# This handles both missing config file AND empty values in existing config file
set_default_config() {
    # Cache and cleanup configuration
    [[ -z "$AUTO_CACHE_CLEANUP" ]] && AUTO_CACHE_CLEANUP=true
    [[ -z "$CACHE_SIZE_THRESHOLD" ]] && CACHE_SIZE_THRESHOLD=100
    
    # Git update configuration  
    [[ -z "$AUTO_GIT_UPDATE" ]] && AUTO_GIT_UPDATE=true
    
    # System paths (empty TEMP_CACHE_DIR means use system default)
    [[ -z "$CONDA_EXE" ]] && CONDA_EXE="/opt/miniconda3/bin/conda"
    
    # Directory configuration
    [[ -z "$MODELS_DIR_DEFAULT" ]] && MODELS_DIR_DEFAULT="${SCRIPT_DIR}/models"
    [[ -z "$CUSTOM_MODELS_DIR" ]] && CUSTOM_MODELS_DIR="/home/g/ai_generation/sdxl/models"
    [[ -z "$AUTO_OUTPUT_VALIDATION" ]] && AUTO_OUTPUT_VALIDATION=true
    
    # Performance configuration
    [[ -z "$DEFAULT_ENABLE_TCMALLOC" ]] && DEFAULT_ENABLE_TCMALLOC=true
    
    # Environment configuration
    [[ -z "$CONDA_ENV_NAME" ]] && CONDA_ENV_NAME="sd-webui-forge"
    [[ -z "$CONDA_ENV_FILE" ]] && CONDA_ENV_FILE="environment-forge.yml"
    
    # Privacy configuration
    [[ -z "$DISABLE_ERROR_REPORTING" ]] && DISABLE_ERROR_REPORTING=true
}

# Load configuration file if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    # Configuration file doesn't exist - we'll show this message later after colors are defined
    CONFIG_FILE_MISSING=true
fi

# Apply defaults for any missing configuration
set_default_config

# WebUI Forge directory (assuming it's in the same parent directory as this script)
WEBUI_DIR="${SCRIPT_DIR}/stable-diffusion-webui-forge"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Pretty print delimiter
delimiter="################################################################"

printf "\n%s\n" "${delimiter}"
printf "${GREEN}Stable Diffusion WebUI Forge - Conda Runner${NC}\n"
printf "${BLUE}Running on CachyOS with conda environment${NC}\n"
printf "%s\n" "${delimiter}"

# Show configuration file status now that colors are available
if [[ "$CONFIG_FILE_MISSING" == "true" ]]; then
    printf "${YELLOW}Configuration file not found: ${CONFIG_FILE}${NC}\n"
    printf "${YELLOW}Using built-in defaults. You can create ${CONFIG_FILE} to customize settings.${NC}\n"
    printf "%s\n" "${delimiter}"
else
    printf "${GREEN}Configuration loaded from: ${CONFIG_FILE}${NC}\n"
    printf "%s\n" "${delimiter}"
fi

# Check if WebUI directory exists, clone if not
if [[ ! -d "${WEBUI_DIR}" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${YELLOW}Stable Diffusion WebUI Forge directory not found. Cloning repository...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Check if git is available
    if ! command -v git &> /dev/null; then
        printf "\n%s\n" "${delimiter}"
        printf "${RED}ERROR: git not found${NC}\n"
        printf "${YELLOW}Solutions:${NC}\n"
        printf "  1. Install git: sudo pacman -S git (Arch/CachyOS)\n"
        printf "  2. Install git: sudo apt install git (Ubuntu/Debian)\n"
        printf "  3. Install git: sudo dnf install git (Fedora)\n"
        printf "%s\n" "${delimiter}"
        exit 1
    fi
    
    # Clone the repository
    git clone https://github.com/lllyasviel/stable-diffusion-webui-forge.git "${WEBUI_DIR}"
    if [[ $? -ne 0 ]]; then
        printf "\n%s\n" "${delimiter}"
        printf "${RED}ERROR: Failed to clone Stable Diffusion WebUI Forge repository${NC}\n"
        printf "${YELLOW}Possible causes and solutions:${NC}\n"
        printf "  1. No internet connection - check your network\n"
        printf "  2. GitHub is down - try again later\n"
        printf "  3. Insufficient disk space - free up space\n"
        printf "  4. Permission issues - check directory permissions\n"
        printf "%s\n" "${delimiter}"
        exit 1
    fi
    
    printf "${GREEN}Successfully cloned Stable Diffusion WebUI Forge repository${NC}\n"
fi

# Smart conda detection: check PATH first, then fall back to configured location
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Detecting conda installation...${NC}\n"
printf "%s\n" "${delimiter}"

# First, try to find conda in PATH
if command -v conda &> /dev/null; then
    CONDA_EXE="conda"
    CONDA_LOCATION=$(which conda)
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
    printf "  3. Update CONDA_EXE in forge-config.sh to point to your conda installation\n"
    printf "  4. If using system conda: sudo pacman -S conda (Arch/CachyOS)\n"
    printf "%s\n" "${delimiter}"
    exit 1
fi

# Environment name (from configuration)
ENV_NAME="$CONDA_ENV_NAME"

# Parse command line arguments
MODELS_DIR=""
OUTPUT_DIR_ARG=""  # Command line override for output directory
ENABLE_TCMALLOC="$DEFAULT_ENABLE_TCMALLOC"  # Default from configuration
FORCE_CACHE_CLEANUP=false  # Force full cache cleanup
DISABLE_GIT_UPDATE=false   # Flag to disable git updates for this run
CUSTOM_ARGS=()

# Process arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --models-dir)
            MODELS_DIR="$2"
            shift 2
            ;;
        --models-dir=*)
            MODELS_DIR="${1#*=}"
            shift
            ;;
        --use-custom-dir|-c)
            MODELS_DIR="$CUSTOM_MODELS_DIR"
            shift
            ;;
        --output-dir)
            OUTPUT_DIR_ARG="$2"
            shift 2
            ;;
        --output-dir=*)
            OUTPUT_DIR_ARG="${1#*=}"
            shift
            ;;
        --disable-tcmalloc)
            ENABLE_TCMALLOC=false
            shift
            ;;
        --clean-cache)
            FORCE_CACHE_CLEANUP=true
            shift
            ;;
        --rebuild-env)
            REBUILD_ENV=true
            shift
            ;;
        --no-git-update)
            DISABLE_GIT_UPDATE=true
            shift
            ;;
        --help|-h)
            printf "${GREEN}Stable Diffusion WebUI Forge Usage:${NC}\n"
            printf "  Default (no args): Use configured default models directory\n"
            printf "  --models-dir PATH: Override the models directory location\n"
            printf "  --use-custom-dir, -c: Use preset custom models dir (from config)\n"
            printf "  --output-dir PATH: Override the output directory for generated images\n"
            printf "  --disable-tcmalloc: Disable TCMalloc (if you experience library conflicts)\n"
            printf "  --clean-cache: Force full cache cleanup on startup\n"
            printf "  --rebuild-env: Remove and rebuild the conda environment\n"
            printf "  --no-git-update: Skip git update for this run\n"
            printf "  --help, -h: Show this help\n"
            printf "\n${GREEN}Configuration:${NC}\n"
            printf "  Edit forge-config.sh to customize settings:\n"
            printf "  • TEMP_CACHE_DIR: Custom temp cache directory\n"
            printf "  • AUTO_CACHE_CLEANUP: Enable/disable automatic cache cleanup\n"
            printf "  • AUTO_GIT_UPDATE: Enable/disable automatic git updates\n"
            printf "  • MODELS_DIR_DEFAULT: Default models directory\n"
            printf "  • OUTPUT_DIR: Default output directory\n"
            printf "  • CONDA_EXE: Path to conda executable\n"
            printf "\n${GREEN}All other arguments are passed to launch.py${NC}\n"
            exit 0
            ;;
        *)
            CUSTOM_ARGS+=("$1")
            shift
            ;;
    esac
done

# Set remaining arguments back
set -- "${CUSTOM_ARGS[@]}"

# Set default models directory if not specified via command line or environment variable
if [[ -z "$MODELS_DIR" ]]; then
    MODELS_DIR="${MODELS_DIR:-$MODELS_DIR_DEFAULT}"  # Use environment variable if set, otherwise use configured default
fi

# Set final output directory with clear priority order:
# 1. Command line argument (--output-dir) - highest priority
# 2. JSON file (output_path.json) 
# 3. Script configuration variable (OUTPUT_DIR)
# 4. WebUI default - lowest priority

if [[ -n "$OUTPUT_DIR_ARG" ]]; then
    # Priority 1: Command line argument
    OUTPUT_DIR="$OUTPUT_DIR_ARG"
    printf "${GREEN}Using output directory from command line: ${OUTPUT_DIR}${NC}\n"
elif [[ -f "${SCRIPT_DIR}/output_path.json" ]]; then
    # Priority 2: JSON file configuration
    printf "${BLUE}Reading output directory from output_path.json...${NC}\n"
    
    # Activate conda environment for python access (if available)
    if "${CONDA_EXE}" env list | grep -q "^${ENV_NAME} "; then
        eval "$("${CONDA_EXE}" shell.bash hook)" 2>/dev/null
        conda activate "${ENV_NAME}" 2>/dev/null
        
        JSON_OUTPUT_DIR=$(python -c "
import json
try:
    with open('${SCRIPT_DIR}/output_path.json', 'r') as f:
        data = json.load(f)
    print(data.get('output_dir', ''))
except Exception as e:
    print('')
" 2>/dev/null)
        
        if [[ -n "$JSON_OUTPUT_DIR" ]]; then
            OUTPUT_DIR="$JSON_OUTPUT_DIR"
            printf "${GREEN}✓ Using output directory from output_path.json: ${OUTPUT_DIR}${NC}\n"
        else
            printf "${YELLOW}Warning: Could not read output_dir from output_path.json${NC}\n"
            # Fall back to script configuration if JSON fails
            if [[ -n "$OUTPUT_DIR" ]]; then
                printf "${BLUE}Falling back to script configuration: ${OUTPUT_DIR}${NC}\n"
            fi
        fi
    else
        printf "${YELLOW}Conda environment not ready - skipping output_path.json${NC}\n"
        # Fall back to script configuration if conda not ready
        if [[ -n "$OUTPUT_DIR" ]]; then
            printf "${BLUE}Falling back to script configuration: ${OUTPUT_DIR}${NC}\n"
        fi
    fi
elif [[ -n "$OUTPUT_DIR" ]]; then
    # Priority 3: Script configuration variable
    printf "${BLUE}Using output directory from script configuration: ${OUTPUT_DIR}${NC}\n"
else
    # Priority 4: WebUI default (OUTPUT_DIR remains empty)
    printf "${BLUE}No custom output directory specified - using WebUI default${NC}\n"
fi

# Handle environment rebuild if requested
if [[ "$REBUILD_ENV" == "true" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${YELLOW}Rebuild environment requested - removing existing conda environment...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Check if environment exists before trying to remove it
    if "${CONDA_EXE}" env list | grep -q "^${ENV_NAME} "; then
        printf "${BLUE}Removing existing conda environment: ${ENV_NAME}${NC}\n"
        "${CONDA_EXE}" env remove -n "${ENV_NAME}" -y
        if [[ $? -eq 0 ]]; then
            printf "${GREEN}Successfully removed conda environment: ${ENV_NAME}${NC}\n"
        else
            printf "\n%s\n" "${delimiter}"
            printf "${RED}ERROR: Failed to remove conda environment: ${ENV_NAME}${NC}\n"
            printf "${YELLOW}Possible solutions:${NC}\n"
            printf "  1. Try manually: conda env remove -n ${ENV_NAME}\n"
            printf "  2. Check if environment is currently active and deactivate it first\n"
            printf "  3. Restart your terminal and try again\n"
            printf "  4. Check conda permissions\n"
            printf "%s\n" "${delimiter}"
            exit 1
        fi
    else
        printf "${YELLOW}Environment ${ENV_NAME} does not exist, will create new one${NC}\n"
    fi
fi

# Check if conda environment exists
if ! "${CONDA_EXE}" env list | grep -q "^${ENV_NAME} "; then
    printf "\n%s\n" "${delimiter}"
    printf "${YELLOW}Conda environment '${ENV_NAME}' not found!${NC}\n"
    printf "Creating conda environment from environment file...\n"
    printf "%s\n" "${delimiter}"
    
    if [[ -f "${SCRIPT_DIR}/${CONDA_ENV_FILE}" ]]; then
        "${CONDA_EXE}" env create -f "${SCRIPT_DIR}/${CONDA_ENV_FILE}"
        if [[ $? -ne 0 ]]; then
            printf "\n%s\n" "${delimiter}"
            printf "${RED}ERROR: Failed to create conda environment${NC}\n"
            printf "${YELLOW}Possible causes and solutions:${NC}\n"
            printf "  1. Network issues - check internet connection\n"
            printf "  2. Disk space - ensure sufficient free space\n"
            printf "  3. Conda channels - try: conda config --add channels conda-forge\n"
            printf "  4. Permission issues - check write permissions\n"
            printf "  5. Corrupted environment file - verify ${CONDA_ENV_FILE}\n"
            printf "%s\n" "${delimiter}"
            exit 1
        fi
        
        printf "\n%s\n" "${delimiter}"
        printf "${GREEN}Installing pip packages from requirements_versions.txt...${NC}\n"
        printf "%s\n" "${delimiter}"
        
        # Activate environment and install pip packages
        eval "$("${CONDA_EXE}" shell.bash hook)"
        conda activate "${ENV_NAME}"
        
        if [[ -f "${WEBUI_DIR}/requirements_versions.txt" ]]; then
            pip install -r "${WEBUI_DIR}/requirements_versions.txt"
            if [[ $? -ne 0 ]]; then
                printf "\n%s\n" "${delimiter}"
                printf "${RED}ERROR: Failed to install pip packages${NC}\n"
                printf "${YELLOW}Possible solutions:${NC}\n"
                printf "  1. Check internet connection\n"
                printf "  2. Try: pip install --upgrade pip\n"
                printf "  3. Clear pip cache: pip cache purge\n"
                printf "  4. Use different index: pip install -i https://pypi.org/simple/\n"
                printf "%s\n" "${delimiter}"
                exit 1
            fi
            
            # Install additional packages that may be missing
            printf "\n${GREEN}Installing additional required packages...${NC}\n"
            pip install joblib
            if [[ $? -ne 0 ]]; then
                printf "\n${YELLOW}Warning: Failed to install joblib package${NC}\n"
            fi
        else
            printf "\n%s\n" "${delimiter}"
            printf "${RED}ERROR: requirements_versions.txt not found in ${WEBUI_DIR}${NC}\n"
            printf "${YELLOW}Possible solutions:${NC}\n"
            printf "  1. Re-clone the repository: rm -rf ${WEBUI_DIR} && git clone ...\n"
            printf "  2. Check if you're in the correct directory\n"
            printf "  3. Verify the repository was cloned completely\n"
            printf "%s\n" "${delimiter}"
            exit 1
        fi
        
        printf "\n${GREEN}Environment setup complete!${NC}\n"
    else
        printf "\n%s\n" "${delimiter}"
        printf "${RED}ERROR: ${CONDA_ENV_FILE} not found in ${SCRIPT_DIR}${NC}\n"
        printf "${YELLOW}Solutions:${NC}\n"
        printf "  1. Create the environment file in the script directory\n"
        printf "  2. Copy from the original Forge repository\n"
        printf "  3. Update CONDA_ENV_FILE in forge-config.sh if using different name\n"
        printf "%s\n" "${delimiter}"
        exit 1
    fi
fi

# Verify conda environment exists
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Verifying conda environment: ${ENV_NAME}${NC}\n"
printf "%s\n" "${delimiter}"

# Check if environment exists
if ! "${CONDA_EXE}" env list | grep -q "^${ENV_NAME} "; then
    printf "\n%s\n" "${delimiter}"
    printf "${RED}ERROR: Conda environment '${ENV_NAME}' not found${NC}\n"
    printf "${YELLOW}This should not happen. Possible solutions:${NC}\n"
    printf "  1. Try running the script again\n"
    printf "  2. Manually create environment: conda env create -f ${CONDA_ENV_FILE}\n"
    printf "  3. Check conda installation: conda --version\n"
    printf "%s\n" "${delimiter}"
    exit 1
fi

printf "${GREEN}Environment ${ENV_NAME} found and ready${NC}\n"

# Change to the WebUI directory
cd "${WEBUI_DIR}" || {
    printf "\n%s\n" "${delimiter}"
    printf "${RED}ERROR: Cannot change to WebUI directory: ${WEBUI_DIR}${NC}\n"
    printf "${YELLOW}Possible solutions:${NC}\n"
    printf "  1. Check if directory exists: ls -la ${WEBUI_DIR}\n"
    printf "  2. Check permissions: ls -ld ${WEBUI_DIR}\n"
    printf "  3. Re-clone repository if corrupted\n"
    printf "%s\n" "${delimiter}"
    exit 1
}

printf "${GREEN}Successfully changed to WebUI directory: ${WEBUI_DIR}${NC}\n"

# Update git repository and check for requirements changes
if [[ "$AUTO_GIT_UPDATE" == "true" ]] && [[ "$DISABLE_GIT_UPDATE" != "true" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Checking for updates...${NC}\n"
    printf "%s\n" "${delimiter}"

    # Store current commit hash
    CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

    # Pull latest changes
    printf "${BLUE}Pulling latest changes from git repository...${NC}\n"
    git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || {
        printf "${YELLOW}Warning: Could not pull from git repository (this is normal if offline)${NC}\n"
    }

    # Check if commit changed
    NEW_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

    if [[ "$CURRENT_COMMIT" != "$NEW_COMMIT" ]] && [[ "$NEW_COMMIT" != "unknown" ]]; then
        printf "${GREEN}Repository updated! Checking if requirements changed...${NC}\n"
        
        # Check if requirements_versions.txt changed in the last commit
        if git diff --name-only HEAD~1 HEAD | grep -q "requirements_versions.txt"; then
            printf "${YELLOW}Requirements file updated! Reinstalling pip packages...${NC}\n"
            # Ensure conda environment is activated for pip updates
            eval "$("${CONDA_EXE}" shell.bash hook)"
            conda activate "${ENV_NAME}"
            pip install -r requirements_versions.txt --upgrade
            if [[ $? -eq 0 ]]; then
                printf "${GREEN}Requirements updated successfully!${NC}\n"
            else
                printf "${RED}Warning: Failed to update some requirements${NC}\n"
            fi
            
            # Ensure additional packages are still installed
            printf "${GREEN}Ensuring additional required packages are installed...${NC}\n"
            pip install joblib
            if [[ $? -ne 0 ]]; then
                printf "${YELLOW}Warning: Failed to install joblib package${NC}\n"
            fi
        else
            printf "${GREEN}No requirements changes detected${NC}\n"
        fi
    else
        printf "${GREEN}Repository is up to date${NC}\n"
    fi
else
    printf "\n%s\n" "${delimiter}"
    printf "${BLUE}Automatic git updates disabled${NC}\n"
    printf "%s\n" "${delimiter}"
fi

# Set local temporary directory (define early so cleanup function can use it)
if [[ -n "$TEMP_CACHE_DIR" ]]; then
    LOCAL_TEMP_DIR="$TEMP_CACHE_DIR"
else
    LOCAL_TEMP_DIR=""
fi

# Cache cleanup function
cleanup_cache() {
    if [[ "$AUTO_CACHE_CLEANUP" != "true" ]] && [[ "$FORCE_CACHE_CLEANUP" != "true" ]]; then
        printf "${BLUE}Automatic cache cleanup disabled (AUTO_CACHE_CLEANUP=false)${NC}\n"
        printf "${BLUE}Use --clean-cache flag to force cleanup if needed${NC}\n"
        return
    fi
    
    printf "${BLUE}Cleaning up cache directories...${NC}\n"
    
    # Clean up system /tmp/gradio cache (the problematic one)
    if [[ -d "/tmp/gradio" ]]; then
        printf "${YELLOW}Removing system Gradio cache: /tmp/gradio${NC}\n"
        rm -rf "/tmp/gradio" 2>/dev/null || printf "${YELLOW}Warning: Could not remove /tmp/gradio${NC}\n"
    fi
    
    # Clean up local temporary cache if it exists and is large (or if forced)
    if [[ -n "$LOCAL_TEMP_DIR" ]] && [[ -d "${LOCAL_TEMP_DIR}" ]]; then
        CACHE_SIZE=$(du -sm "${LOCAL_TEMP_DIR}" 2>/dev/null | cut -f1 || echo "0")
        if [[ $CACHE_SIZE -gt $CACHE_SIZE_THRESHOLD ]] || [[ "$FORCE_CACHE_CLEANUP" == "true" ]]; then
            if [[ "$FORCE_CACHE_CLEANUP" == "true" ]]; then
                printf "${YELLOW}Force cleaning local temp cache (${CACHE_SIZE}MB)...${NC}\n"
            else
                printf "${YELLOW}Local temp cache is ${CACHE_SIZE}MB (threshold: ${CACHE_SIZE_THRESHOLD}MB), cleaning up...${NC}\n"
            fi
            rm -rf "${LOCAL_TEMP_DIR}"/* 2>/dev/null || printf "${YELLOW}Warning: Could not clean local cache${NC}\n"
        else
            printf "${GREEN}Local temp cache size: ${CACHE_SIZE}MB (threshold: ${CACHE_SIZE_THRESHOLD}MB, keeping)${NC}\n"
        fi
    elif [[ -z "$LOCAL_TEMP_DIR" ]]; then
        printf "${BLUE}No custom temp directory configured - skipping custom cache cleanup${NC}\n"
    fi
    
    # Clean up Python cache
    if [[ -d "${WEBUI_DIR}/__pycache__" ]]; then
        printf "${YELLOW}Cleaning Python cache...${NC}\n"
        find "${WEBUI_DIR}" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
        find "${WEBUI_DIR}" -name "*.pyc" -delete 2>/dev/null || true
    fi
    
    printf "${GREEN}Cache cleanup completed${NC}\n"
}

# Validation function for output directories
validate_output_paths() {
    if [[ "$AUTO_OUTPUT_VALIDATION" != "true" ]] || [[ -z "$OUTPUT_DIR" ]]; then
        if [[ -z "$OUTPUT_DIR" ]]; then
            printf "${BLUE}No custom output directory specified - using WebUI default${NC}\n"
        else
            printf "${BLUE}Output directory validation disabled (AUTO_OUTPUT_VALIDATION=false)${NC}\n"
        fi
        return 0
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Validating output directory configuration...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    printf "${BLUE}Checking output directory: ${OUTPUT_DIR}${NC}\n"
    
    # Check if output directory exists
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        printf "${YELLOW}Output directory does not exist: ${OUTPUT_DIR}${NC}\n"
        printf "${BLUE}Creating output directory...${NC}\n"
        
        if mkdir -p "$OUTPUT_DIR" 2>/dev/null; then
            printf "${GREEN}✓ Successfully created output directory: ${OUTPUT_DIR}${NC}\n"
        else
            printf "${RED}ERROR: Failed to create output directory: ${OUTPUT_DIR}${NC}\n"
            printf "${YELLOW}Please check parent directory permissions${NC}\n"
            printf "${BLUE}You can create it manually with: mkdir -p \"${OUTPUT_DIR}\"${NC}\n"
            exit 1
        fi
    else
        printf "${GREEN}✓ Output directory exists: ${OUTPUT_DIR}${NC}\n"
    fi
    
    # Test write permissions
    if [[ ! -w "$OUTPUT_DIR" ]]; then
        printf "${RED}ERROR: No write permission for output directory: ${OUTPUT_DIR}${NC}\n"
        printf "${YELLOW}Please check directory permissions${NC}\n"
        exit 1
    else
        printf "${GREEN}✓ Output directory is writable${NC}\n"
    fi
    
    # Create subdirectories that WebUI expects
    local subdirs=("txt2img-images" "img2img-images" "txt2img-grids" "img2img-grids" "extras-images")
    printf "${BLUE}Ensuring output subdirectories exist...${NC}\n"
    
    for subdir in "${subdirs[@]}"; do
        local full_path="${OUTPUT_DIR}/${subdir}"
        if mkdir -p "$full_path" 2>/dev/null; then
            printf "${GREEN}✓ ${subdir}${NC}\n"
        else
            printf "${YELLOW}Warning: Could not create subdirectory: ${subdir}${NC}\n"
        fi
    done
    
    printf "${GREEN}Output directory validation completed successfully${NC}\n"
}

# Configuration sync function for models directories
sync_models_config() {
    if [[ -z "$MODELS_DIR" ]]; then
        printf "${BLUE}No custom models directory specified - skipping models configuration sync${NC}\n"
        return 0
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Synchronizing models directory configuration...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    local config_file="${WEBUI_DIR}/config.json"
    
    # Check if config.json exists
    if [[ ! -f "$config_file" ]]; then
        printf "${YELLOW}config.json not found - skipping models configuration sync${NC}\n"
        return 0
    fi
    
    printf "${BLUE}Models directory: ${MODELS_DIR}${NC}\n"
    printf "${GREEN}✓ Models configuration noted${NC}\n"
}

# Configuration sync function for output directories
sync_output_config() {
    if [[ -z "$OUTPUT_DIR" ]]; then
        printf "${BLUE}No custom output directory specified - skipping configuration sync${NC}\n"
        return 0
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Synchronizing output directory configuration...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    local config_file="${WEBUI_DIR}/config.json"
    
    # Check if config.json exists
    if [[ ! -f "$config_file" ]]; then
        printf "${YELLOW}config.json not found - creating new configuration${NC}\n"
        
        # Create basic config with output directories
        cat > "$config_file" << EOF
{
    "outdir_samples": "",
    "outdir_txt2img_samples": "${OUTPUT_DIR}/txt2img-images",
    "outdir_img2img_samples": "${OUTPUT_DIR}/img2img-images",
    "outdir_extras_samples": "${OUTPUT_DIR}/extras-images",
    "outdir_grids": "",
    "outdir_txt2img_grids": "${OUTPUT_DIR}/txt2img-grids",
    "outdir_img2img_grids": "${OUTPUT_DIR}/img2img-grids",
    "outdir_save": "${OUTPUT_DIR}/saved"
}
EOF
        
        if [[ $? -eq 0 ]]; then
            printf "${GREEN}✓ Created new config.json with output directory settings${NC}\n"
        else
            printf "${RED}ERROR: Failed to create config.json${NC}\n"
            return 1
        fi
        return 0
    fi
    
    printf "${BLUE}Output directory configuration will be handled by WebUI${NC}\n"
    printf "${GREEN}✓ Output configuration noted${NC}\n"
}

# Set up cleanup trap for script exit
cleanup_on_exit() {
    printf "\n${YELLOW}Stable Diffusion WebUI Forge is shutting down...${NC}\n"
    cleanup_cache
    printf "${GREEN}Cleanup completed. Goodbye!${NC}\n"
}

# Register cleanup function to run on script exit
trap cleanup_on_exit EXIT INT TERM

# Set up temporary directories using correct environment variable
# TMPDIR is the standard Unix environment variable that Python's tempfile module respects
if [[ -n "$LOCAL_TEMP_DIR" ]]; then
    export TMPDIR="${LOCAL_TEMP_DIR}"
    mkdir -p "${LOCAL_TEMP_DIR}"
    printf "${GREEN}Temp directories configured:${NC}\n"
    printf "  System temp (TMPDIR): ${TMPDIR}\n"
    printf "  This will redirect Gradio cache from /tmp/gradio to custom directory${NC}\n"
else
    printf "${GREEN}No custom temp directory configured - using system default${NC}\n"
    printf "${BLUE}Application will use its own preferred temp directory${NC}\n"
fi

# Set environment variables to prevent the webui from trying to install dependencies
# Note: We don't set SKIP_PREPARE_ENVIRONMENT=1 on first run to allow repository cloning
export REQS_FILE="/dev/null/nonexistent_requirements.txt"  # Point to non-existent file to skip requirements
export TORCH_COMMAND=""  # Don't install torch

# Check if repositories exist, if not, allow first-time setup
REPOS_DIR="${WEBUI_DIR}/repositories"
if [[ ! -d "${REPOS_DIR}/huggingface_guess" ]] || [[ ! -d "${REPOS_DIR}/BLIP" ]]; then
    printf "${YELLOW}Missing required repositories. Allowing first-time repository setup...${NC}\n"
    printf "${YELLOW}This will clone huggingface_guess and BLIP repositories but won't install Python packages${NC}\n"
    SKIP_ENV_PREPARE=0
else
    printf "${GREEN}Required repositories found. Skipping environment preparation...${NC}\n"
    SKIP_ENV_PREPARE=1
fi

# Disable venv creation since we're using conda
export venv_dir="-"

# Set python command to use conda's python
python_cmd="python"

# Disable sentry logging (if configured)
if [[ "$DISABLE_ERROR_REPORTING" == "true" ]]; then
    export ERROR_REPORTING=FALSE
fi

# GPU detection for CachyOS (similar to original script but adapted for conda)
gpu_info=$(lspci 2>/dev/null | grep -E "VGA|Display")
case "$gpu_info" in
    *"Navi 1"*)
        export HSA_OVERRIDE_GFX_VERSION=10.3.0
        printf "${YELLOW}Detected AMD Navi 1 GPU - Setting HSA_OVERRIDE_GFX_VERSION=10.3.0${NC}\n"
    ;;
    *"Navi 2"*) 
        export HSA_OVERRIDE_GFX_VERSION=10.3.0
        printf "${YELLOW}Detected AMD Navi 2 GPU - Setting HSA_OVERRIDE_GFX_VERSION=10.3.0${NC}\n"
    ;;
    *"Navi 3"*) 
        printf "${YELLOW}Detected AMD Navi 3 GPU${NC}\n"
    ;;
    *"Renoir"*) 
        export HSA_OVERRIDE_GFX_VERSION=9.0.0
        printf "${YELLOW}Detected AMD Renoir - Setting HSA_OVERRIDE_GFX_VERSION=9.0.0${NC}\n"
        printf "${YELLOW}Make sure to have at least 4GB VRAM and 10GB RAM${NC}\n"
    ;;
    *"NVIDIA"*)
        printf "${GREEN}Detected NVIDIA GPU${NC}\n"
    ;;
    *)
        printf "${YELLOW}GPU detection: Unknown or no discrete GPU detected${NC}\n"
    ;;
esac

# TCMalloc setup (from original script) - with conda compatibility fix
prepare_tcmalloc() {
    if [[ "${OSTYPE}" == "linux"* ]] && [[ -z "${NO_TCMALLOC}" ]] && [[ -z "${LD_PRELOAD}" ]]; then
        # Check if we're using conda - enable temporary shell integration for TCMalloc (default behavior)
        if [[ -n "${CONDA_EXE}" ]]; then
            if [[ "${ENABLE_TCMALLOC}" == "false" ]]; then
                printf "${YELLOW}TCMalloc disabled by --disable-tcmalloc flag${NC}\n"
                return
            else
                printf "${GREEN}Enabling TCMalloc with temporary conda shell integration...${NC}\n"
                eval "$("${CONDA_EXE}" shell.bash hook)"
                conda activate "${ENV_NAME}" 2>/dev/null || {
                    printf "${RED}Warning: Could not activate conda environment for TCMalloc${NC}\n"
                    return
                }
            fi
        fi
        
        LIBC_VER=$(echo $(ldd --version | awk 'NR==1 {print $NF}') | grep -oP '\d+\.\d+')
        echo "glibc version is $LIBC_VER"
        libc_vernum=$(expr $LIBC_VER)
        libc_v234=2.34
        TCMALLOC_LIBS=("libtcmalloc(_minimal|)\.so\.\d" "libtcmalloc\.so\.\d")
        
        for lib in "${TCMALLOC_LIBS[@]}"; do
            TCMALLOC="$(PATH=/sbin:/usr/sbin:$PATH ldconfig -p | grep -P $lib | head -n 1)"
            TC_INFO=(${TCMALLOC//=>/})
            if [[ ! -z "${TC_INFO}" ]]; then
                echo "Check TCMalloc: ${TC_INFO}"
                # Additional check for library compatibility
                if ldd ${TC_INFO[2]} 2>/dev/null | grep -q 'GLIBCXX_3.4.30'; then
                    printf "${YELLOW}TCMalloc requires GLIBCXX_3.4.30 - skipping to avoid conflicts${NC}\n"
                    break
                fi
                
                if [ $(echo "$libc_vernum < $libc_v234" | bc) -eq 1 ]; then
                    if ldd ${TC_INFO[2]} | grep -q 'libpthread'; then
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
    fi
}

# Activate conda environment for the main application
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Activating conda environment for Stable Diffusion WebUI Forge...${NC}\n"
printf "%s\n" "${delimiter}"

eval "$("${CONDA_EXE}" shell.bash hook)"
conda activate "${ENV_NAME}"

if [[ $? -ne 0 ]]; then
    printf "\n${RED}ERROR: Failed to activate conda environment '${ENV_NAME}'${NC}\n"
    exit 1
fi

# Validate output directories before proceeding
validate_output_paths

# Perform startup cache cleanup
printf "\n%s\n" "${delimiter}"
if [[ "$AUTO_CACHE_CLEANUP" == "true" ]] || [[ "$FORCE_CACHE_CLEANUP" == "true" ]]; then
    printf "${GREEN}Performing startup cache cleanup...${NC}\n"
else
    printf "${BLUE}Startup cache cleanup disabled (AUTO_CACHE_CLEANUP=false)${NC}\n"
fi
printf "%s\n" "${delimiter}"
cleanup_cache

# Synchronize output directory configuration
sync_output_config

# Synchronize models directory configuration
sync_models_config

# Launch the application
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Launching Stable Diffusion WebUI Forge...${NC}\n"
printf "${BLUE}Using conda environment: ${CONDA_DEFAULT_ENV}${NC}\n"
printf "${BLUE}Python: $(which python)${NC}\n"
printf "${BLUE}Working directory: ${WEBUI_DIR}${NC}\n"
if [[ -n "$MODELS_DIR" ]]; then
    printf "${BLUE}Models directory: ${MODELS_DIR}${NC}\n"
else
    printf "${BLUE}Models directory: Using WebUI default${NC}\n"
fi
if [[ -n "$OUTPUT_DIR" ]]; then
    printf "${BLUE}Output directory: ${OUTPUT_DIR}${NC}\n"
else
    printf "${BLUE}Output directory: Using WebUI default${NC}\n"
fi
printf "%s\n" "${delimiter}"

# Prepare TCMalloc
prepare_tcmalloc

# Set up restart loop (from original script)
KEEP_GOING=1
export SD_WEBUI_RESTART=tmp/restart

while [[ "$KEEP_GOING" -eq "1" ]]; do
    # Launch the application with all passed arguments
    # Conditionally skip environment preparation based on repository status
    # --no-download-sd-model prevents automatic model downloads
    # --no-hashing skips model file verification for faster startup
    # --cuda-malloc enables CUDA memory allocation
    # Build launch arguments
    LAUNCH_ARGS=(--no-download-sd-model --no-hashing --cuda-malloc)
    
    # Add models directory if specified
    if [[ -n "$MODELS_DIR" ]]; then
        LAUNCH_ARGS+=(--models-dir "$MODELS_DIR")
    fi
    
    if [[ "$SKIP_ENV_PREPARE" -eq "1" ]]; then
        "${python_cmd}" -u launch.py --skip-prepare-environment "${LAUNCH_ARGS[@]}" "$@"
    else
        printf "${YELLOW}First run: Allowing repository setup but preventing Python package installation${NC}\n"
        "${python_cmd}" -u launch.py "${LAUNCH_ARGS[@]}" "$@"
    fi
    
    if [[ ! -f tmp/restart ]]; then
        KEEP_GOING=0
    fi
done

printf "\n%s\n" "${delimiter}"
printf "${GREEN}Stable Diffusion WebUI Forge session ended${NC}\n"
printf "%s\n" "${delimiter}"
