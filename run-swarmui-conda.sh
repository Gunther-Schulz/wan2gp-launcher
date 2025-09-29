#!/bin/bash
#########################################################
# SwarmUI - Conda Environment Runner
# This script manages the conda environment and runs SwarmUI
# with .NET 8 SDK support
#
# Usage:
#   ./run-swarmui-conda.sh [options] [other SwarmUI args...]
#
# Options:
#   --models-dir PATH      Override the models directory location
#   --use-custom-dir, -c   Use preset custom models dir (from config)
#   --output-dir PATH      Override the output directory for generated images
#   --clean-cache          Force full cache cleanup on startup
#   --host HOST            Set host address (default: localhost)
#   --port PORT            Set port number (default: 7801)
#   --launch-mode MODE     Set launch mode (web, none, or cloudflared)
#   --rebuild-env          Remove and rebuild the conda environment
#   --no-git-update        Skip git update for this run
#
# Examples:
#   ./run-swarmui-conda.sh                              # Use configured default models dir
#   ./run-swarmui-conda.sh -c                          # Use preset custom models dir (shorthand)
#   ./run-swarmui-conda.sh --use-custom-dir             # Use preset custom models dir (full)
#   ./run-swarmui-conda.sh --models-dir /path/to/models # Use specific models dir
#   ./run-swarmui-conda.sh --output-dir /path/to/output # Use specific output dir
#   ./run-swarmui-conda.sh --clean-cache                # Force cache cleanup
#   ./run-swarmui-conda.sh --host 0.0.0.0 --port 7801  # Remote access
#   MODELS_DIR=/path/to/models ./run-swarmui-conda.sh   # Use environment variable
#########################################################

#########################################################
# Configuration Loading
#########################################################

# Get the directory where this script is located (needed for config file path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from external config file
CONFIG_FILE="${SCRIPT_DIR}/swarmui-config.sh"

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
    
    # Network configuration
    [[ -z "$DEFAULT_HOST" ]] && DEFAULT_HOST="localhost"
    [[ -z "$DEFAULT_PORT" ]] && DEFAULT_PORT="7801"
    [[ -z "$DEFAULT_LAUNCH_MODE" ]] && DEFAULT_LAUNCH_MODE="web"
    
    # Environment configuration
    [[ -z "$CONDA_ENV_NAME" ]] && CONDA_ENV_NAME="swarmui"
    [[ -z "$CONDA_ENV_FILE" ]] && CONDA_ENV_FILE="environment-swarmui.yml"
    
    # Privacy configuration
    [[ -z "$DISABLE_ERROR_REPORTING" ]] && DISABLE_ERROR_REPORTING=true
    
    # Network settings (passed as launch parameters, not FDS editing)
    # FDS editing removed - we use symlinks for paths and parameters for network
    
    # Forge compatibility
    [[ -z "$USE_FORGE_MODEL_COMPATIBILITY" ]] && USE_FORGE_MODEL_COMPATIBILITY=false
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

# SwarmUI directory (assuming it's in the same parent directory as this script)
SWARMUI_DIR="${SCRIPT_DIR}/SwarmUI"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Pretty print delimiter
delimiter="################################################################"

printf "\n%s\n" "${delimiter}"
printf "${GREEN}SwarmUI - Conda Runner${NC}\n"
printf "${BLUE}Running on CachyOS with conda environment and .NET 8${NC}\n"
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

# Check if SwarmUI directory exists, clone if not
if [[ ! -d "${SWARMUI_DIR}" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${YELLOW}SwarmUI directory not found. Cloning repository...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Check if git is available
    if ! command -v git &> /dev/null; then
        printf "\n${RED}ERROR: git is not installed or not in PATH${NC}\n"
        printf "Please install git first\n"
        exit 1
    fi
    
    # Clone the repository
    git clone https://github.com/mcmonkeyprojects/SwarmUI.git "${SWARMUI_DIR}"
    if [[ $? -ne 0 ]]; then
        printf "\n${RED}ERROR: Failed to clone SwarmUI repository${NC}\n"
        printf "Please check your internet connection and try again\n"
        exit 1
    fi
    
    printf "${GREEN}Successfully cloned SwarmUI repository${NC}\n"
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
    printf "  3. Update CONDA_EXE in swarmui-config.sh to point to your conda installation\n"
    printf "  4. If using system conda: sudo pacman -S conda (Arch/CachyOS)\n"
    printf "%s\n" "${delimiter}"
    exit 1
fi

# .NET 8 SDK will be provided by conda environment - check after activation

# Environment name (from configuration)
ENV_NAME="$CONDA_ENV_NAME"

# Parse command line arguments
MODELS_DIR=""
OUTPUT_DIR_ARG=""  # Command line override for output directory
FORCE_CACHE_CLEANUP=false  # Force full cache cleanup
DISABLE_GIT_UPDATE=false   # Flag to disable git updates for this run
HOST_ARG=""
PORT_ARG=""
LAUNCH_MODE_ARG=""
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
        --host)
            HOST_ARG="$2"
            shift 2
            ;;
        --host=*)
            HOST_ARG="${1#*=}"
            shift
            ;;
        --port)
            PORT_ARG="$2"
            shift 2
            ;;
        --port=*)
            PORT_ARG="${1#*=}"
            shift
            ;;
        --launch-mode)
            LAUNCH_MODE_ARG="$2"
            shift 2
            ;;
        --launch-mode=*)
            LAUNCH_MODE_ARG="${1#*=}"
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
            printf "${GREEN}SwarmUI Conda Launcher Usage:${NC}\n"
            printf "\n${BLUE}Launcher Options:${NC}\n"
            printf "  --host HOST: Set host address (default: ${DEFAULT_HOST})\n"
            printf "  --port PORT: Set port number (default: ${DEFAULT_PORT})\n"
            printf "  --launch-mode MODE: Set launch mode (web, none, or cloudflared)\n"
            printf "  --clean-cache: Force full cache cleanup on startup\n"
            printf "  --rebuild-env: Remove and rebuild the conda environment\n"
            printf "  --no-git-update: Skip git update for this run\n"
            printf "  --help, -h: Show this help\n"
            printf "\n${YELLOW}Note: Models and output directories are configured through SwarmUI's web interface${NC}\n"
            printf "${YELLOW}Legacy --models-dir and --output-dir flags are ignored (SwarmUI doesn't support them)${NC}\n"
            printf "\n${GREEN}Configuration:${NC}\n"
            printf "  Edit swarmui-config.sh to customize settings:\n"
            printf "  • TEMP_CACHE_DIR: Custom temp cache directory\n"
            printf "  • AUTO_CACHE_CLEANUP: Enable/disable automatic cache cleanup\n"
            printf "  • AUTO_GIT_UPDATE: Enable/disable automatic git updates\n"
            printf "  • CONDA_EXE: Path to conda executable\n"
            printf "  • DEFAULT_HOST, DEFAULT_PORT: Network settings\n"
            printf "\n${GREEN}SwarmUI Arguments (passed through):${NC}\n"
            printf "  --data_dir PATH: Override data directory\n"
            printf "  --environment MODE: development or production\n"
            printf "  --loglevel LEVEL: Debug, Info, Warning, Error\n"
            printf "  See SwarmUI docs for complete argument list\n"
            printf "\n${GREEN}After launch, configure models/outputs at: http://localhost:7801${NC}\n"
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

# Set final output directory with clear priority order:
# 1. Command line argument (--output-dir) - highest priority
# 2. JSON file (output_path.json) 
# 3. Script configuration variable (OUTPUT_DIR)
# 4. SwarmUI default - lowest priority

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
    # Priority 4: SwarmUI default (OUTPUT_DIR remains empty)
    printf "${BLUE}No custom output directory specified - using SwarmUI default${NC}\n"
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
        printf "${GREEN}Conda environment created successfully!${NC}\n"
        printf "${BLUE}Environment includes .NET 8 SDK and minimal Python for integration scripts${NC}\n"
        printf "%s\n" "${delimiter}"
    else
        printf "\n%s\n" "${delimiter}"
        printf "${RED}ERROR: ${CONDA_ENV_FILE} not found in ${SCRIPT_DIR}${NC}\n"
        printf "${YELLOW}Solutions:${NC}\n"
        printf "  1. Create the environment file in the script directory\n"
        printf "  2. Copy from the SwarmUI repository if available\n"
        printf "  3. Update CONDA_ENV_FILE in swarmui-config.sh if using different name\n"
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
    printf "\n${RED}ERROR: Conda environment '${ENV_NAME}' not found${NC}\n"
    exit 1
fi

printf "${GREEN}Environment ${ENV_NAME} found and ready${NC}\n"

# Change to the SwarmUI directory
cd "${SWARMUI_DIR}" || {
    printf "\n${RED}ERROR: Cannot change to SwarmUI directory: ${SWARMUI_DIR}${NC}\n"
    exit 1
}

# Update git repository and check for changes
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
        printf "${GREEN}Repository updated!${NC}\n"
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
    
    # Clean up system /tmp cache
    if [[ -d "/tmp/swarmui" ]]; then
        printf "${YELLOW}Removing system SwarmUI cache: /tmp/swarmui${NC}\n"
        rm -rf "/tmp/swarmui" 2>/dev/null || printf "${YELLOW}Warning: Could not remove /tmp/swarmui${NC}\n"
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
    
    # Clean up SwarmUI specific cache directories
    if [[ -d "${SWARMUI_DIR}/Data/Cache" ]]; then
        printf "${YELLOW}Cleaning SwarmUI cache...${NC}\n"
        rm -rf "${SWARMUI_DIR}/Data/Cache"/* 2>/dev/null || true
    fi
    
    printf "${GREEN}Cache cleanup completed${NC}\n"
}

# Validation function for output directories
validate_output_paths() {
    if [[ "$AUTO_OUTPUT_VALIDATION" != "true" ]] || [[ -z "$OUTPUT_DIR" ]]; then
        if [[ -z "$OUTPUT_DIR" ]]; then
            printf "${BLUE}No custom output directory specified - using SwarmUI default${NC}\n"
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
    
    printf "${GREEN}Output directory validation completed successfully${NC}\n"
}

# Set up cleanup trap for script exit
cleanup_on_exit() {
    printf "\n${YELLOW}SwarmUI is shutting down...${NC}\n"
    cleanup_cache
    printf "${GREEN}Cleanup completed. Goodbye!${NC}\n"
}

# Register cleanup function to run on script exit
trap cleanup_on_exit EXIT INT TERM

# Set up temporary directories using correct environment variable
# TMPDIR is the standard Unix environment variable
if [[ -n "$LOCAL_TEMP_DIR" ]]; then
    export TMPDIR="${LOCAL_TEMP_DIR}"
    mkdir -p "${LOCAL_TEMP_DIR}"
    printf "${GREEN}Temp directories configured:${NC}\n"
    printf "  System temp (TMPDIR): ${TMPDIR}\n"
    printf "  This will redirect cache from default location to custom directory${NC}\n"
else
    printf "${GREEN}No custom temp directory configured - using system default${NC}\n"
    printf "${BLUE}Application will use its own preferred temp directory${NC}\n"
fi

# GPU detection for CachyOS (similar to original script but adapted for SwarmUI)
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

# Activate conda environment for the main application
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Activating conda environment for SwarmUI...${NC}\n"
printf "%s\n" "${delimiter}"

eval "$("${CONDA_EXE}" shell.bash hook)"
conda activate "${ENV_NAME}"

if [[ $? -ne 0 ]]; then
    printf "\n${RED}ERROR: Failed to activate conda environment '${ENV_NAME}'${NC}\n"
    exit 1
fi

# Verify .NET 8 SDK is available in conda environment
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Verifying .NET 8 SDK in conda environment...${NC}\n"
printf "%s\n" "${delimiter}"

if ! command -v dotnet &> /dev/null; then
    printf "\n${RED}ERROR: .NET SDK not found in conda environment${NC}\n"
    printf "${YELLOW}This should not happen. Try rebuilding the environment with --rebuild-env${NC}\n"
    exit 1
fi

# Verify .NET version
DOTNET_VERSION=$(dotnet --version 2>/dev/null | cut -d. -f1)
if [[ "$DOTNET_VERSION" -lt 8 ]]; then
    printf "\n${RED}ERROR: .NET 8 or higher is required (found version: $(dotnet --version 2>/dev/null || echo 'unknown'))${NC}\n"
    printf "${YELLOW}Try rebuilding the environment with --rebuild-env${NC}\n"
    exit 1
fi

printf "${GREEN}✓ .NET SDK version: $(dotnet --version)${NC}\n"

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


# Function to set up Forge model folder compatibility
setup_forge_compatibility() {
    if [[ "$USE_FORGE_MODEL_COMPATIBILITY" != "true" ]]; then
        return 0
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Setting up Forge model folder compatibility...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Auto-detect Forge models path if not specified
    local forge_models_path="$FORGE_MODELS_PATH"
    if [[ -z "$forge_models_path" ]]; then
        forge_models_path="${SCRIPT_DIR}/models"
        printf "${BLUE}Auto-detecting Forge models path: ${forge_models_path}${NC}\n"
    else
        printf "${BLUE}Using configured Forge models path: ${forge_models_path}${NC}\n"
    fi
    
    # Check if Forge models directory exists
    if [[ ! -d "$forge_models_path" ]]; then
        printf "${RED}ERROR: Forge models directory not found: ${forge_models_path}${NC}\n"
        printf "${YELLOW}Please check FORGE_MODELS_PATH in your config or disable USE_FORGE_MODEL_COMPATIBILITY${NC}\n"
        return 1
    fi
    
    local swarmui_models_dir="${SWARMUI_DIR}/Models"
    
    # Create SwarmUI Models directory if it doesn't exist
    mkdir -p "$swarmui_models_dir"
    
    printf "${BLUE}Creating symlinks for compatible model folders...${NC}\n"
    
    # Define the mapping between SwarmUI and Forge folder names
    # Format: "swarmui_folder:forge_folder:description"
    local folder_mappings=(
        "Stable-Diffusion:Stable-diffusion:Stable Diffusion checkpoints"
        "Lora:Lora:LoRA models"
        "VAE:VAE:VAE models"
        "controlnet:ControlNet:ControlNet models"
        "upscale_models:ESRGAN:ESRGAN upscaling models"
        "upscale_models:RealESRGAN:RealESRGAN upscaling models (fallback)"
    )
    
    local links_created=0
    local links_skipped=0
    
    for mapping in "${folder_mappings[@]}"; do
        IFS=':' read -r swarm_folder forge_folder description <<< "$mapping"
        
        local swarm_path="${swarmui_models_dir}/${swarm_folder}"
        local forge_path="${forge_models_path}/${forge_folder}"
        
        # Check if Forge folder exists
        if [[ ! -d "$forge_path" ]]; then
            printf "${YELLOW}  Skipping ${swarm_folder} -> ${forge_folder} (Forge folder not found)${NC}\n"
            ((links_skipped++))
            continue
        fi
        
        # Handle special case for upscale_models (multiple sources)
        if [[ "$swarm_folder" == "upscale_models" ]]; then
            # Only create the link if it doesn't exist yet (prefer ESRGAN over RealESRGAN)
            if [[ -L "$swarm_path" ]] || [[ -d "$swarm_path" ]]; then
                printf "${YELLOW}  Skipping ${swarm_folder} -> ${forge_folder} (already exists)${NC}\n"
                ((links_skipped++))
                continue
            fi
        fi
        
        # Move any existing models to Forge directory before creating symlink
        if [[ -d "$swarm_path" && ! -L "$swarm_path" ]]; then
            if [[ "$(ls -A "$swarm_path" 2>/dev/null)" ]]; then
                printf "${YELLOW}  Moving existing models from ${swarm_folder} to Forge directory...${NC}\n"
                mkdir -p "$forge_path"
                mv "$swarm_path"/* "$forge_path"/ 2>/dev/null || true
                printf "${GREEN}  ✓ Moved existing models to ${forge_path}${NC}\n"
            fi
        fi
        
        # Remove existing directory/symlink and create new symlink
        rm -rf "$swarm_path"
        # Create the symlink
        if ln -s "$forge_path" "$swarm_path" 2>/dev/null; then
            printf "${GREEN}  ✓ Created: ${swarm_folder} -> ${forge_folder} (${description})${NC}\n"
            ((links_created++))
        else
            printf "${RED}  ✗ Failed: ${swarm_folder} -> ${forge_folder}${NC}\n"
            ((links_skipped++))
        fi
    done
    
    printf "\n${GREEN}Forge compatibility setup complete:${NC}\n"
    printf "${GREEN}  Links created: ${links_created}${NC}\n"
    if [[ $links_skipped -gt 0 ]]; then
        printf "${YELLOW}  Links skipped: ${links_skipped}${NC}\n"
    fi
    
    printf "\n${BLUE}Note: SwarmUI-specific folders (diffusion_models, clip, etc.) remain separate${NC}\n"
    printf "${BLUE}Modern models (Flux, SD3) should be placed in SwarmUI/Models/diffusion_models${NC}\n"
}

# Function to set up custom output directory symlink
setup_output_directory() {
    if [[ -z "$OUTPUT_DIR" ]]; then
        return 0
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Setting up custom output directory...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # SwarmUI uses OutputPath setting from Settings.fds, which defaults to "Output" (relative to SwarmUI root)
    # This is different from the Data/Output directory
    local swarmui_output_dir="${SWARMUI_DIR}/Output"
    
    # Create SwarmUI directory if it doesn't exist
    mkdir -p "$SWARMUI_DIR"
    
    # Check if custom output directory exists
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        printf "${YELLOW}Custom output directory doesn't exist, creating: ${OUTPUT_DIR}${NC}\n"
        if ! mkdir -p "$OUTPUT_DIR"; then
            printf "${RED}ERROR: Failed to create output directory: ${OUTPUT_DIR}${NC}\n"
            return 1
        fi
    fi
    
    # Move any existing outputs to custom directory before creating symlink
    if [[ -d "$swarmui_output_dir" && ! -L "$swarmui_output_dir" ]]; then
        if [[ "$(ls -A "$swarmui_output_dir" 2>/dev/null)" ]]; then
            printf "${YELLOW}Moving existing outputs to custom directory...${NC}\n"
            mkdir -p "$OUTPUT_DIR"
            mv "$swarmui_output_dir"/* "$OUTPUT_DIR"/ 2>/dev/null || true
            printf "${GREEN}✓ Moved existing outputs to ${OUTPUT_DIR}${NC}\n"
        fi
    fi
    
    # Remove existing directory/symlink and create new symlink
    rm -rf "$swarmui_output_dir"
    
    # Create symlink to custom output directory
    if ln -s "$OUTPUT_DIR" "$swarmui_output_dir" 2>/dev/null; then
        printf "${GREEN}✓ Created output symlink: ${swarmui_output_dir} -> ${OUTPUT_DIR}${NC}\n"
    else
        printf "${RED}✗ Failed to create output symlink${NC}\n"
        return 1
    fi
}

# Function to set up custom models root (independent of Forge)
setup_custom_models_root() {
    if [[ -z "$CUSTOM_MODELS_ROOT" ]]; then
        return 0
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Setting up custom models root directory...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Check if custom models root exists
    if [[ ! -d "$CUSTOM_MODELS_ROOT" ]]; then
        printf "${YELLOW}Custom models root doesn't exist, creating: ${CUSTOM_MODELS_ROOT}${NC}\n"
        if ! mkdir -p "$CUSTOM_MODELS_ROOT"; then
            printf "${RED}ERROR: Failed to create custom models root: ${CUSTOM_MODELS_ROOT}${NC}\n"
            return 1
        fi
    fi
    
    local swarmui_models_dir="${SWARMUI_DIR}/Models"
    mkdir -p "$swarmui_models_dir"
    
    printf "${BLUE}Using custom models root: ${CUSTOM_MODELS_ROOT}${NC}\n"
    
    # Standard SwarmUI model folder names
    local swarmui_folders=(
        "Stable-Diffusion"
        "Lora" 
        "VAE"
        "controlnet"
        "upscale_models"
        "diffusion_models"
        "clip"
        "clip_vision"
        "style_models"
        "Embeddings"
    )
    
    local links_created=0
    local links_skipped=0
    
    for folder in "${swarmui_folders[@]}"; do
        local swarm_path="${swarmui_models_dir}/${folder}"
        local custom_path="${CUSTOM_MODELS_ROOT}/${folder}"
        
        # Create custom folder if it doesn't exist
        mkdir -p "$custom_path"
        
        # Move any existing models to custom location before creating symlink
        if [[ -d "$swarm_path" && ! -L "$swarm_path" ]]; then
            if [[ "$(ls -A "$swarm_path" 2>/dev/null)" ]]; then
                printf "${YELLOW}  Moving existing models from ${folder} to custom location...${NC}\n"
                mv "$swarm_path"/* "$custom_path"/ 2>/dev/null || true
                printf "${GREEN}  ✓ Moved existing models to ${custom_path}${NC}\n"
            fi
        fi
        
        # Remove existing directory/symlink and create new symlink
        rm -rf "$swarm_path"
        
        # Create the symlink
        if ln -s "$custom_path" "$swarm_path" 2>/dev/null; then
            printf "${GREEN}  ✓ Created: ${folder} -> ${custom_path}${NC}\n"
            ((links_created++))
        else
            printf "${RED}  ✗ Failed: ${folder} -> ${custom_path}${NC}\n"
            ((links_skipped++))
        fi
    done
    
    printf "\n${GREEN}Custom models root setup complete:${NC}\n"
    printf "${GREEN}  Links created: ${links_created}${NC}\n"
    if [[ $links_skipped -gt 0 ]]; then
        printf "${YELLOW}  Links skipped: ${links_skipped}${NC}\n"
    fi
    
    printf "\n${BLUE}Your models are now organized in: ${CUSTOM_MODELS_ROOT}${NC}\n"
}

# Set up model folder compatibility (with conflict detection)
if [[ "$USE_FORGE_MODEL_COMPATIBILITY" == "true" ]] && [[ -n "$CUSTOM_MODELS_ROOT" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${YELLOW}WARNING: Both Forge compatibility and custom models root are enabled!${NC}\n"
    printf "${YELLOW}This may cause conflicts. Choose one approach:${NC}\n"
    printf "${BLUE}  1. Forge compatibility: USE_FORGE_MODEL_COMPATIBILITY=true, CUSTOM_MODELS_ROOT=\"\"${NC}\n"
    printf "${BLUE}  2. Custom models root: USE_FORGE_MODEL_COMPATIBILITY=false, CUSTOM_MODELS_ROOT=\"/path\"${NC}\n"
    printf "${YELLOW}Proceeding with Forge compatibility (takes priority)...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Forge takes priority, disable custom models root for this run
    CUSTOM_MODELS_ROOT=""
fi

# Set up Forge model folder compatibility (if enabled)
setup_forge_compatibility

# Set up custom models root (if specified and not conflicting)
setup_custom_models_root

# Set up custom output directory (if specified)
setup_output_directory

# Launch the application
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Launching SwarmUI...${NC}\n"
printf "${BLUE}Using conda environment: ${CONDA_DEFAULT_ENV}${NC}\n"
printf "${BLUE}Python: $(which python)${NC}\n"
printf "${BLUE}.NET: $(which dotnet) (version: $(dotnet --version))${NC}\n"
printf "${BLUE}Working directory: ${SWARMUI_DIR}${NC}\n"
if [[ -n "$MODELS_DIR" ]]; then
    printf "${BLUE}Models directory: ${MODELS_DIR}${NC}\n"
else
    printf "${BLUE}Models directory: Using SwarmUI default${NC}\n"
fi
if [[ -n "$OUTPUT_DIR" ]]; then
    printf "${BLUE}Output directory: ${OUTPUT_DIR}${NC}\n"
else
    printf "${BLUE}Output directory: Using SwarmUI default${NC}\n"
fi
printf "%s\n" "${delimiter}"

# Build launch arguments (only SwarmUI-supported arguments)
LAUNCH_ARGS=()

# Set up custom data directory symlinks if specified
if [[ -n "$SWARMUI_DATA_DIR" ]]; then
    LAUNCH_ARGS+=(--data_dir "$SWARMUI_DATA_DIR")
fi

# Add host (use argument or default)
if [[ -n "$HOST_ARG" ]]; then
    LAUNCH_ARGS+=(--host "$HOST_ARG")
elif [[ -n "$DEFAULT_HOST" ]] && [[ "$DEFAULT_HOST" != "localhost" ]]; then
    LAUNCH_ARGS+=(--host "$DEFAULT_HOST")
fi

# Add port (use argument or default)
if [[ -n "$PORT_ARG" ]]; then
    LAUNCH_ARGS+=(--port "$PORT_ARG")
elif [[ -n "$DEFAULT_PORT" ]] && [[ "$DEFAULT_PORT" != "7801" ]]; then
    LAUNCH_ARGS+=(--port "$DEFAULT_PORT")
fi

# Add launch mode (use argument or default)
if [[ -n "$LAUNCH_MODE_ARG" ]]; then
    LAUNCH_ARGS+=(--launch_mode "$LAUNCH_MODE_ARG")
elif [[ -n "$DEFAULT_LAUNCH_MODE" ]] && [[ "$DEFAULT_LAUNCH_MODE" != "web" ]]; then
    LAUNCH_ARGS+=(--launch_mode "$DEFAULT_LAUNCH_MODE")
fi

# Launch SwarmUI using its official launch script with conda-provided .NET 8 SDK
printf "${GREEN}Using SwarmUI's official launch script with conda-provided .NET 8 SDK${NC}\n"
printf "${BLUE}Launch arguments: ${LAUNCH_ARGS[*]} $*${NC}\n"

# Check if SwarmUI's launch script exists
if [[ ! -f "launch-linux.sh" ]]; then
    printf "\n${RED}ERROR: launch-linux.sh not found in SwarmUI directory${NC}\n"
    printf "${YELLOW}Make sure you're in the SwarmUI directory and the repository is complete${NC}\n"
    exit 1
fi

# Make sure launch script is executable
chmod +x launch-linux.sh

# Launch SwarmUI with its official script, passing all our arguments
printf "${BLUE}Launching SwarmUI with official launch script...${NC}\n"
./launch-linux.sh "${LAUNCH_ARGS[@]}" "$@"

printf "\n%s\n" "${delimiter}"
printf "${GREEN}SwarmUI session ended${NC}\n"
printf "%s\n" "${delimiter}"
