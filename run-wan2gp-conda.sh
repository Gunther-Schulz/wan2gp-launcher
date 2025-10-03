#!/bin/bash
#########################################################
# Wan2GP - Conda Environment Runner
# This script activates the conda environment and runs Wan2GP
# without trying to install dependencies itself
#########################################################

#########################################################
# Configuration Loading
#########################################################

# Get the directory where this script is located (needed for config file path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from external config file
CONFIG_FILE="${SCRIPT_DIR}/wan2gp-config.sh"

# Set fallback defaults in case config file is missing or incomplete
# This handles both missing config file AND empty values in existing config file
set_default_config() {
    # Cache and cleanup configuration
    [[ -z "$AUTO_CACHE_CLEANUP" ]] && AUTO_CACHE_CLEANUP=false
    [[ -z "$CACHE_SIZE_THRESHOLD" ]] && CACHE_SIZE_THRESHOLD=100
    
    # Git update configuration  
    [[ -z "$AUTO_GIT_UPDATE" ]] && AUTO_GIT_UPDATE=true
    
    # System paths (empty TEMP_CACHE_DIR means use system default)
    [[ -z "$CONDA_EXE" ]] && CONDA_EXE="/opt/miniconda3/bin/conda"
    
    # Save path configuration - always let app use its own defaults
    # Only set paths if explicitly configured in config file
    # Empty or missing values = let the Wan2GP app decide everything
    
    # Advanced configuration
    [[ -z "$DEFAULT_SAGE_VERSION" ]] && DEFAULT_SAGE_VERSION="2"
    [[ -z "$DEFAULT_ENABLE_TCMALLOC" ]] && DEFAULT_ENABLE_TCMALLOC=true
    [[ -z "$DEFAULT_SERVER_PORT" ]] && DEFAULT_SERVER_PORT="7862"
    
    # Build configuration
    [[ -z "$SAGE_PARALLEL_JOBS" ]] && SAGE_PARALLEL_JOBS=4
    [[ -z "$SAGE_NVCC_THREADS" ]] && SAGE_NVCC_THREADS=8
    [[ -z "$SAGE_MAX_JOBS" ]] && SAGE_MAX_JOBS=8
    
    # Repository configuration
    [[ -z "$OFFICIAL_REPO_URL" ]] && OFFICIAL_REPO_URL="https://github.com/deepbeepmeep/Wan2GP.git"
    # OFFICIAL_REPO_BRANCH can be intentionally empty (uses default branch)
    [[ -z "$CUSTOM_REPO_URL" ]] && CUSTOM_REPO_URL="https://github.com/Gunther-Schulz/Wan2GP.git"
    [[ -z "$CUSTOM_REPO_BRANCH" ]] && CUSTOM_REPO_BRANCH="combined-features"
    
    # Environment configuration
    [[ -z "$CONDA_ENV_NAME" ]] && CONDA_ENV_NAME="wan2gp"
    [[ -z "$CONDA_ENV_FILE" ]] && CONDA_ENV_FILE="environment-wan2gp.yml"
    
    # GPU configuration
    [[ -z "$AMD_NAVI1_GFX_VERSION" ]] && AMD_NAVI1_GFX_VERSION="10.3.0"
    [[ -z "$AMD_NAVI2_GFX_VERSION" ]] && AMD_NAVI2_GFX_VERSION="10.3.0"
    [[ -z "$AMD_RENOIR_GFX_VERSION" ]] && AMD_RENOIR_GFX_VERSION="9.0.0"
    
    # Error reporting
    [[ -z "$DISABLE_ERROR_REPORTING" ]] && DISABLE_ERROR_REPORTING=true
    
    # TCMalloc configuration
    [[ -z "$TCMALLOC_GLIBC_THRESHOLD" ]] && TCMALLOC_GLIBC_THRESHOLD="2.34"
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

# Wan2GP directory (assuming it's in the same parent directory as this script)
WAN2GP_DIR="${SCRIPT_DIR}/Wan2GP"

# Early parsing of flags that need to be processed before environment checks
REBUILD_ENV=false
DISABLE_GIT_UPDATE=false
SAGE_VERSION="$DEFAULT_SAGE_VERSION"  # Start with default from config
for arg in "$@"; do
    case $arg in
        --rebuild-env)
            REBUILD_ENV=true
            ;;
        --no-git-update)
            DISABLE_GIT_UPDATE=true
            ;;
        --sage3)
            SAGE_VERSION="3"
            ;;
        --sage2)
            SAGE_VERSION="2"
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Pretty print delimiter
delimiter="################################################################"

printf "\n%s\n" "${delimiter}"
printf "${GREEN}Wan2GP - AI Video Generator - Conda Runner${NC}\n"
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

# Check if Wan2GP directory exists, clone if not
if [[ ! -d "${WAN2GP_DIR}" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${YELLOW}Wan2GP directory not found. First-time setup required.${NC}\n"
    printf "%s\n" "${delimiter}"

    # Check if git is available
    if ! command -v git &> /dev/null; then
        printf "\n${RED}ERROR: git is not installed or not in PATH${NC}\n"
        printf "Please install git first\n"
        exit 1
    fi

    # Repository selection menu
    printf "\n${GREEN}Please select which Wan2GP repository to clone:${NC}\n"
    printf "${BLUE}1) Official Repository${NC} (deepbeepmeep/Wan2GP)\n"
    printf "   - Standard Wan2GP with all official models\n"
    printf "   - Regular updates and community support\n"
    printf "\n${BLUE}2) Custom Fork${NC} (Gunther-Schulz/Wan2GP)\n"
    printf "   - Includes support for WAN2.2-14B-Rapid-AllInOne Mega-v3\n"
    printf "   - Additional model support from Phr00t\n"
    printf "   - Fork of the official repository\n"
    printf "\n"

    # Get user choice
    while true; do
        printf "${YELLOW}Enter your choice (1 or 2): ${NC}"
        read -r choice
        case $choice in
            1)
                REPO_URL="$OFFICIAL_REPO_URL"
                REPO_NAME="Official Repository (deepbeepmeep/Wan2GP)"
                REPO_BRANCH="$OFFICIAL_REPO_BRANCH"
                break
                ;;
            2)
                REPO_URL="$CUSTOM_REPO_URL"
                REPO_NAME="Custom Fork (with Mega-v3 support)"
                REPO_BRANCH="$CUSTOM_REPO_BRANCH"
                break
                ;;
            *)
                printf "${RED}Invalid choice. Please enter 1 or 2.${NC}\n"
                ;;
        esac
    done

    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Cloning ${REPO_NAME}...${NC}\n"
    printf "${BLUE}Repository URL: ${REPO_URL}${NC}\n"
    if [[ -n "${REPO_BRANCH}" ]]; then
        printf "${BLUE}Branch: ${REPO_BRANCH}${NC}\n"
    fi
    printf "%s\n" "${delimiter}"

    # Clone the selected repository
    if [[ -n "${REPO_BRANCH}" ]]; then
        git clone -b "${REPO_BRANCH}" "${REPO_URL}" "${WAN2GP_DIR}"
    else
        git clone "${REPO_URL}" "${WAN2GP_DIR}"
    fi
    if [[ $? -ne 0 ]]; then
        printf "\n${RED}ERROR: Failed to clone Wan2GP repository${NC}\n"
        printf "Please check your internet connection and try again\n"
        exit 1
    fi

    printf "${GREEN}Successfully cloned ${REPO_NAME}${NC}\n"
    printf "${BLUE}Location: ${WAN2GP_DIR}${NC}\n"
    
    # Show additional info for custom fork
    if [[ "$choice" == "2" ]]; then
        printf "\n${GREEN}Additional Features Available:${NC}\n"
        printf "${BLUE}• WAN2.2-14B-Rapid-AllInOne Mega-v3 model support${NC}\n"
        printf "${BLUE}• Enhanced model compatibility from Phr00t's collection${NC}\n"
        printf "${BLUE}• Download models from: https://huggingface.co/Phr00t/WAN2.2-14B-Rapid-AllInOne/tree/main/Mega-v3${NC}\n"
    fi
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
    printf "  1. Install conda/miniconda/anaconda and ensure it's in PATH\n"
    printf "  2. Update CONDA_EXE in wan2gp-config.sh to point to your conda installation\n"
    printf "  3. Activate your conda environment before running this script\n"
    printf "%s\n" "${delimiter}"
    exit 1
fi

# Environment name (from configuration)
ENV_NAME="$CONDA_ENV_NAME"

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
            printf "${RED}ERROR: Failed to remove conda environment: ${ENV_NAME}${NC}\n"
            printf "You may need to remove it manually with: conda env remove -n ${ENV_NAME}${NC}\n"
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
            printf "\n${RED}ERROR: Failed to create conda environment${NC}\n"
            exit 1
        fi

        printf "\n%s\n" "${delimiter}"
        printf "${GREEN}Installing pip packages from requirements.txt...${NC}\n"
        printf "%s\n" "${delimiter}"

        # Activate environment and install pip packages
        printf "${GREEN}Installing pip packages in conda environment...${NC}\n"
        eval "$("${CONDA_EXE}" shell.bash hook)"
        conda activate "${ENV_NAME}"

        if [[ -f "${WAN2GP_DIR}/requirements.txt" ]]; then
            pip install -r "${WAN2GP_DIR}/requirements.txt"
            if [[ $? -ne 0 ]]; then
                printf "\n${RED}ERROR: Failed to install pip packages${NC}\n"
                exit 1
            fi
        else
            printf "\n${RED}ERROR: requirements.txt not found in ${WAN2GP_DIR}${NC}\n"
            exit 1
        fi

        # Install attention optimization packages
        printf "\n%s\n" "${delimiter}"
        printf "${GREEN}Installing attention optimization packages...${NC}\n"
        printf "%s\n" "${delimiter}"
        
        # Install Flash Attention (latest version works better with PyTorch 2.8)
        printf "${BLUE}Installing Flash Attention (latest)...${NC}\n"
        pip install flash-attn
        if [[ $? -eq 0 ]]; then
            printf "${GREEN}Flash Attention installed successfully${NC}\n"
        else
            printf "${YELLOW}Warning: Failed to install Flash Attention (this is normal on some systems)${NC}\n"
        fi
        
        # Install SageAttention (compile from source for best performance)
        if [[ "$SAGE_VERSION" == "3" ]]; then
            printf "${BLUE}Installing SageAttention3 from HuggingFace (microscaling FP4 attention)...${NC}\n"
            printf "${YELLOW}Requirements: Python >=3.13, PyTorch >=2.8.0, CUDA >=12.8${NC}\n"
        else
            printf "${BLUE}Installing SageAttention 2.2.0 (SageAttention2++) from GitHub...${NC}\n"
            printf "${BLUE}Requirements: Python >=3.9, PyTorch >=2.0, CUDA >=12.0${NC}\n"
        fi
        
        # Check CUDA availability first
        if ! command -v nvcc &> /dev/null; then
            if [[ "$SAGE_VERSION" == "3" ]]; then
                printf "${YELLOW}Warning: NVCC not found. SageAttention requires CUDA for compilation.${NC}\n"
            else
                printf "${YELLOW}Warning: NVCC not found. SageAttention 2.2.0 requires CUDA for compilation.${NC}\n"
            fi
            printf "${YELLOW}Skipping SageAttention installation. You can install manually later.${NC}\n"
        else
            # Set CUDA_HOME to conda environment to avoid version mismatch
            export CUDA_HOME="${CONDA_PREFIX}"
            printf "${BLUE}Setting CUDA_HOME to conda environment: ${CUDA_HOME}${NC}\n"
            
            # Verify CUDA version compatibility
            CONDA_CUDA_VERSION=$(nvcc --version | grep "release" | sed 's/.*release \([0-9]\+\.[0-9]\+\).*/\1/')
            printf "${BLUE}Using CUDA version: ${CONDA_CUDA_VERSION}${NC}\n"
            
            # Check CUDA version requirements
            if [[ "$SAGE_VERSION" == "3" ]]; then
                printf "${BLUE}Experimental branch may require CUDA >=12.8 for Blackwell features${NC}\n"
            else
                printf "${BLUE}SageAttention 2.2.0 requires CUDA >=12.0${NC}\n"
            fi
            
            # First, ensure we have build dependencies
            printf "${BLUE}Installing build dependencies...${NC}\n"
            pip install ninja packaging wheel setuptools
            
            # Clone and install SageAttention
            SAGE_DIR="/tmp/SageAttention"
            if [[ -d "$SAGE_DIR" ]]; then
                rm -rf "$SAGE_DIR"
            fi
            
            # Handle different SageAttention versions - different repositories!
            if [[ "$SAGE_VERSION" == "3" ]]; then
                # SageAttention 3 - from HuggingFace repository
                printf "${BLUE}Cloning SageAttention3 from HuggingFace...${NC}\n"
                printf "${YELLOW}Note: SageAttention3 requires Python >=3.13 and PyTorch >=2.8.0${NC}\n"
                
                # Check Python version
                PYTHON_VERSION=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
                printf "${BLUE}Current Python version: ${PYTHON_VERSION}${NC}\n"
                if [[ $(python -c "import sys; print(1 if sys.version_info >= (3, 13) else 0)") == "0" ]]; then
                    printf "${RED}ERROR: SageAttention3 requires Python 3.13 or higher${NC}\n"
                    printf "${YELLOW}Current Python version: ${PYTHON_VERSION}${NC}\n"
                    printf "${YELLOW}Please update environment-wan2gp.yml to use Python 3.13${NC}\n"
                    printf "${YELLOW}Falling back to SageAttention 2.2.0 installation...${NC}\n"
                    SAGE_VERSION="2"
                fi
                
                # Check PyTorch version
                PYTORCH_VERSION=$(python -c "import torch; print(torch.__version__.split('+')[0])" 2>/dev/null || echo "not_installed")
                if [[ "$PYTORCH_VERSION" != "not_installed" ]]; then
                    printf "${BLUE}Current PyTorch version: ${PYTORCH_VERSION}${NC}\n"
                    if [[ $(python -c "v='${PYTORCH_VERSION}'.split('.'); print(1 if int(v[0]) > 2 or (int(v[0]) == 2 and int(v[1]) >= 8) else 0)") == "0" ]]; then
                        printf "${YELLOW}WARNING: SageAttention3 requires PyTorch 2.8.0 or higher${NC}\n"
                        printf "${YELLOW}Current PyTorch version: ${PYTORCH_VERSION}${NC}\n"
                        printf "${YELLOW}Installation may fail. Consider upgrading PyTorch.${NC}\n"
                    fi
                fi
                
                if [[ "$SAGE_VERSION" == "3" ]]; then
                    git clone https://huggingface.co/jt-zhang/SageAttention3 "$SAGE_DIR"
                    if [[ $? -eq 0 ]]; then
                        cd "$SAGE_DIR"
                        printf "${GREEN}Successfully cloned SageAttention3 from HuggingFace${NC}\n"
                        
                        # Set parallel compilation for faster build
                        export EXT_PARALLEL="$SAGE_PARALLEL_JOBS"
                        export NVCC_APPEND_FLAGS="--threads $SAGE_NVCC_THREADS" 
                        export MAX_JOBS="$SAGE_MAX_JOBS"
                        
                        printf "${BLUE}Compiling SageAttention3 (this may take several minutes)...${NC}\n"
                        printf "${BLUE}Using CUDA_HOME: ${CUDA_HOME}${NC}\n"
                        printf "${BLUE}Features: Microscaling FP4 attention for Blackwell GPUs${NC}\n"
                        python setup.py install
                        
                        if [[ $? -eq 0 ]]; then
                            printf "${GREEN}SageAttention3 installed successfully!${NC}\n"
                            printf "${GREEN}Features: FP4 Tensor Cores with up to 5x speedup on RTX 5090${NC}\n"
                            cd "${WAN2GP_DIR}"
                            rm -rf "$SAGE_DIR"
                        else
                            printf "${RED}ERROR: Failed to compile SageAttention3${NC}\n"
                            printf "${YELLOW}This may be due to:${NC}\n"
                            printf "${YELLOW}  - Python version <3.13 (SageAttention3 requires >=3.13)${NC}\n"
                            printf "${YELLOW}  - PyTorch version <2.8.0 (SageAttention3 requires >=2.8.0)${NC}\n"
                            printf "${YELLOW}  - CUDA version <12.8 (SageAttention3 requires >=12.8)${NC}\n"
                            printf "${YELLOW}  - Missing development tools or insufficient memory${NC}\n"
                            printf "${YELLOW}Wan2GP will work without SageAttention3, but may be slower.${NC}\n"
                            cd "${WAN2GP_DIR}"
                            rm -rf "$SAGE_DIR"
                        fi
                    else
                        printf "${RED}ERROR: Failed to clone SageAttention3 from HuggingFace${NC}\n"
                        printf "${YELLOW}The repository may be gated (requires approval)${NC}\n"
                        printf "${YELLOW}Visit: https://huggingface.co/jt-zhang/SageAttention3${NC}\n"
                        printf "${YELLOW}Wan2GP will work without SageAttention3.${NC}\n"
                    fi
                fi
            fi
            
            # Install SageAttention 2.2.0 if version 3 wasn't requested or fell back
            if [[ "$SAGE_VERSION" == "2" ]]; then
                printf "${BLUE}Cloning SageAttention 2.2.0 from GitHub...${NC}\n"
                git clone https://github.com/thu-ml/SageAttention.git "$SAGE_DIR"
                if [[ $? -eq 0 ]]; then
                    cd "$SAGE_DIR"
                    printf "${BLUE}Installing SageAttention 2.2.0 with SageAttention2++ features...${NC}\n"
                    
                    # Set parallel compilation for faster build
                    export EXT_PARALLEL="$SAGE_PARALLEL_JOBS"
                    export NVCC_APPEND_FLAGS="--threads $SAGE_NVCC_THREADS" 
                    export MAX_JOBS="$SAGE_MAX_JOBS"
                    
                    printf "${BLUE}Compiling SageAttention 2.2.0 (this may take several minutes)...${NC}\n"
                    printf "${BLUE}Using CUDA_HOME: ${CUDA_HOME}${NC}\n"
                    python setup.py install
                    
                    if [[ $? -eq 0 ]]; then
                        printf "${GREEN}SageAttention 2.2.0 installed successfully${NC}\n"
                        printf "${GREEN}Features: 2-5x speedup, per-thread quantization, outlier smoothing${NC}\n"
                        cd "${WAN2GP_DIR}"
                        rm -rf "$SAGE_DIR"
                    else
                        printf "${RED}ERROR: Failed to compile SageAttention 2.2.0${NC}\n"
                        printf "${YELLOW}This may be due to:${NC}\n"
                        printf "${YELLOW}  - CUDA version mismatch between system and PyTorch${NC}\n"
                        printf "${YELLOW}  - Missing development tools${NC}\n"
                        printf "${YELLOW}  - Insufficient memory during compilation${NC}\n"
                        printf "${YELLOW}Wan2GP will work without SageAttention, but may be slower.${NC}\n"
                        cd "${WAN2GP_DIR}"
                        rm -rf "$SAGE_DIR"
                    fi
                else
                    printf "${RED}ERROR: Failed to clone SageAttention 2.2.0 repository${NC}\n"
                    printf "${YELLOW}Check your internet connection. Wan2GP will work without SageAttention.${NC}\n"
                fi
            fi
        fi
        

        printf "\n${GREEN}Environment setup complete!${NC}\n"
    else
        printf "\n${RED}ERROR: ${CONDA_ENV_FILE} not found in ${SCRIPT_DIR}${NC}\n"
        printf "Please make sure the environment file exists in the Wan2GP directory\n"
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

# Change to the Wan2GP directory
cd "${WAN2GP_DIR}" || {
    printf "\n${RED}ERROR: Cannot change to Wan2GP directory: ${WAN2GP_DIR}${NC}\n"
    exit 1
}

# Update git repository and check for requirements changes
if [[ "$AUTO_GIT_UPDATE" == "true" ]] && [[ "$DISABLE_GIT_UPDATE" != "true" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Checking for updates...${NC}\n"
    printf "%s\n" "${delimiter}"

    # Store current commit hash
    CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

    # Pull latest changes
    printf "${BLUE}Pulling latest changes from git repository...${NC}\n"
    
    # Detect which repository we're using by checking the remote URL
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$REMOTE_URL" == *"Gunther-Schulz/Wan2GP"* ]]; then
        # Gunther-Schulz fork uses combined-features branch
        TARGET_BRANCH="combined-features"
        printf "${BLUE}Detected Gunther-Schulz fork - using ${TARGET_BRANCH} branch${NC}\n"
        
        # Check current branch and switch if needed
        CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
        if [[ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]]; then
            printf "${YELLOW}Currently on branch '${CURRENT_BRANCH}', switching to '${TARGET_BRANCH}'...${NC}\n"
            git checkout "$TARGET_BRANCH" 2>/dev/null || {
                printf "${YELLOW}Warning: Could not switch to ${TARGET_BRANCH} branch${NC}\n"
            }
        fi
        
        # Pull from the correct branch
        git pull origin "$TARGET_BRANCH" 2>/dev/null || {
            printf "${YELLOW}Warning: Could not pull from ${TARGET_BRANCH} branch (this is normal if offline)${NC}\n"
        }
    else
        # Official repository uses main or master
        printf "${BLUE}Detected official repository - using main/master branch${NC}\n"
        git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || {
            printf "${YELLOW}Warning: Could not pull from git repository (this is normal if offline)${NC}\n"
        }
    fi
else
    printf "\n%s\n" "${delimiter}"
    printf "${BLUE}Automatic git updates disabled${NC}\n"
    printf "%s\n" "${delimiter}"
    CURRENT_COMMIT="disabled"
    NEW_COMMIT="disabled"
fi

# Check if commit changed (only if git updates are enabled)
if [[ "$AUTO_GIT_UPDATE" == "true" ]] && [[ "$DISABLE_GIT_UPDATE" != "true" ]]; then
    NEW_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
else
    NEW_COMMIT="disabled"
fi

if [[ "$CURRENT_COMMIT" != "$NEW_COMMIT" ]] && [[ "$NEW_COMMIT" != "unknown" ]] && [[ "$NEW_COMMIT" != "disabled" ]]; then
    printf "${GREEN}Repository updated! Checking if requirements changed...${NC}\n"

    # Check if requirements.txt changed in the last commit
    if git diff --name-only HEAD~1 HEAD | grep -q "requirements.txt"; then
        printf "${YELLOW}Requirements file updated! Reinstalling pip packages...${NC}\n"
        # Ensure conda environment is activated for pip updates
        eval "$("${CONDA_EXE}" shell.bash hook)"
        conda activate "${ENV_NAME}"
        pip install -r requirements.txt --upgrade
        if [[ $? -eq 0 ]]; then
            printf "${GREEN}Requirements updated successfully!${NC}\n"
        else
            printf "${RED}Warning: Failed to update some requirements${NC}\n"
        fi
        
        # Also update attention packages when requirements change
        printf "${BLUE}Updating attention optimization packages...${NC}\n"
        pip install flash-attn --upgrade 2>/dev/null && printf "${GREEN}Flash Attention updated${NC}\n" || printf "${YELLOW}Flash Attention update skipped${NC}\n"
        
        # Update SageAttention from source if possible
        printf "${BLUE}Updating SageAttention from source...${NC}\n"
        if command -v nvcc &> /dev/null; then
            # Set CUDA_HOME to conda environment to avoid version mismatch
            export CUDA_HOME="${CONDA_PREFIX}"
            SAGE_DIR="/tmp/SageAttention_update"
            
            # Determine which SageAttention version to update based on config
            if [[ "$DEFAULT_SAGE_VERSION" == "3" ]]; then
                # Try to update SageAttention3 from HuggingFace
                printf "${BLUE}Attempting to update SageAttention3 from HuggingFace...${NC}\n"
                if git clone https://huggingface.co/jt-zhang/SageAttention3 "$SAGE_DIR" 2>/dev/null; then
                    cd "$SAGE_DIR"
                    export EXT_PARALLEL="$SAGE_PARALLEL_JOBS" NVCC_APPEND_FLAGS="--threads $SAGE_NVCC_THREADS" MAX_JOBS="$SAGE_MAX_JOBS"
                    python setup.py install 2>/dev/null && printf "${GREEN}SageAttention3 updated from source${NC}\n" || printf "${YELLOW}SageAttention3 source update failed${NC}\n"
                    cd "${WAN2GP_DIR}"
                    rm -rf "$SAGE_DIR"
                else
                    printf "${YELLOW}SageAttention3 update skipped (repository may be gated or offline)${NC}\n"
                fi
            else
                # Update SageAttention 2.2.0 from GitHub
                if git clone https://github.com/thu-ml/SageAttention.git "$SAGE_DIR" 2>/dev/null; then
                    cd "$SAGE_DIR"
                    export EXT_PARALLEL="$SAGE_PARALLEL_JOBS" NVCC_APPEND_FLAGS="--threads $SAGE_NVCC_THREADS" MAX_JOBS="$SAGE_MAX_JOBS"
                    python setup.py install 2>/dev/null && printf "${GREEN}SageAttention 2.2.0 updated from source${NC}\n" || printf "${YELLOW}SageAttention source update failed${NC}\n"
                    cd "${WAN2GP_DIR}"
                    rm -rf "$SAGE_DIR"
                else
                    printf "${YELLOW}SageAttention update skipped (clone failed)${NC}\n"
                fi
            fi
        else
            printf "${YELLOW}SageAttention update skipped (no CUDA compiler)${NC}\n"
        fi
        
    else
        printf "${GREEN}No requirements changes detected${NC}\n"
    fi
else
    if [[ "$AUTO_GIT_UPDATE" == "true" ]] && [[ "$DISABLE_GIT_UPDATE" != "true" ]]; then
        printf "${GREEN}Repository is up to date${NC}\n"
    else
        printf "${BLUE}Git updates disabled - repository not checked${NC}\n"
    fi
fi

# GPU detection for CachyOS (adapted from forge script)
gpu_info=$(lspci 2>/dev/null | grep -E "VGA|Display")
case "$gpu_info" in
    *"Navi 1"*)
        export HSA_OVERRIDE_GFX_VERSION="$AMD_NAVI1_GFX_VERSION"
        printf "${YELLOW}Detected AMD Navi 1 GPU - Setting HSA_OVERRIDE_GFX_VERSION=${AMD_NAVI1_GFX_VERSION}${NC}\n"
    ;;
    *"Navi 2"*)
        export HSA_OVERRIDE_GFX_VERSION="$AMD_NAVI2_GFX_VERSION"
        printf "${YELLOW}Detected AMD Navi 2 GPU - Setting HSA_OVERRIDE_GFX_VERSION=${AMD_NAVI2_GFX_VERSION}${NC}\n"
    ;;
    *"Navi 3"*)
        printf "${YELLOW}Detected AMD Navi 3 GPU${NC}\n"
    ;;
    *"Renoir"*)
        export HSA_OVERRIDE_GFX_VERSION="$AMD_RENOIR_GFX_VERSION"
        printf "${YELLOW}Detected AMD Renoir - Setting HSA_OVERRIDE_GFX_VERSION=${AMD_RENOIR_GFX_VERSION}${NC}\n"
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
        libc_v234="$TCMALLOC_GLIBC_THRESHOLD"
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

# Set local temporary directory (define early so cleanup function can use it)
# Only use custom temp directory if explicitly configured
if [[ -n "$TEMP_CACHE_DIR" ]]; then
    LOCAL_TEMP_DIR="$TEMP_CACHE_DIR"
else
    # No custom temp directory configured - let system/app decide
    LOCAL_TEMP_DIR=""
fi

# Validation function for save paths
validate_save_paths() {
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Validating save path configurations...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    local save_path_file="${SCRIPT_DIR}/save_path.json"
    local save_path=""
    local image_save_path=""
    local config_source=""
    
    # Try to read from save_path.json first
    if [[ -f "$save_path_file" ]]; then
        printf "${BLUE}Found save_path.json - reading paths...${NC}\n"
        
        # Activate conda environment for python access
        eval "$("${CONDA_EXE}" shell.bash hook)" 2>/dev/null
        conda activate "${ENV_NAME}" 2>/dev/null
        
        # Extract values using python
        save_path=$(python -c "
import json
try:
    with open('${save_path_file}', 'r') as f:
        data = json.load(f)
    print(data.get('save_path', ''))
except Exception as e:
    print('')
" 2>/dev/null)
        
        image_save_path=$(python -c "
import json
try:
    with open('${save_path_file}', 'r') as f:
        data = json.load(f)
    print(data.get('image_save_path', ''))
except Exception as e:
    print('')
" 2>/dev/null)
        
        if [[ -n "$save_path" ]] && [[ -n "$image_save_path" ]]; then
            config_source="save_path.json"
            printf "${GREEN}Successfully read paths from save_path.json${NC}\n"
        else
            printf "${YELLOW}Warning: Could not read valid paths from save_path.json${NC}\n"
        fi
    fi
    
    # Fall back to script variables if save_path.json failed or doesn't exist
    if [[ -z "$save_path" ]] || [[ -z "$image_save_path" ]]; then
        if [[ -n "$SCRIPT_SAVE_PATH" ]] && [[ -n "$SCRIPT_IMAGE_SAVE_PATH" ]]; then
            save_path="$SCRIPT_SAVE_PATH"
            image_save_path="$SCRIPT_IMAGE_SAVE_PATH"
            config_source="script variables"
            printf "${BLUE}Using save paths from script variables${NC}\n"
        else
            printf "${GREEN}No save paths configured - letting Wan2GP use its own defaults${NC}\n"
            printf "${BLUE}Skipping path validation - application will choose its own locations${NC}\n"
            return 0
        fi
    fi
    
    printf "${BLUE}Checking save paths from ${config_source}:${NC}\n"
    printf "  save_path: ${save_path}\n"
    printf "  image_save_path: ${image_save_path}\n"
    
    # Validate video save path
    if [[ ! -d "$save_path" ]]; then
        printf "${RED}ERROR: Video save path does not exist: ${save_path}${NC}\n"
        printf "${YELLOW}Please create the directory or update save_path.json${NC}\n"
        printf "${BLUE}You can create it with: mkdir -p \"${save_path}\"${NC}\n"
        exit 1
    else
        printf "${GREEN}✓ Video save path exists: ${save_path}${NC}\n"
    fi
    
    # Validate image save path
    if [[ ! -d "$image_save_path" ]]; then
        printf "${RED}ERROR: Image save path does not exist: ${image_save_path}${NC}\n"
        printf "${YELLOW}Please create the directory or update save_path.json${NC}\n"
        printf "${BLUE}You can create it with: mkdir -p \"${image_save_path}\"${NC}\n"
        exit 1
    else
        printf "${GREEN}✓ Image save path exists: ${image_save_path}${NC}\n"
    fi
    
    # Test write permissions
    if [[ ! -w "$save_path" ]]; then
        printf "${RED}ERROR: No write permission for video save path: ${save_path}${NC}\n"
        printf "${YELLOW}Please check directory permissions${NC}\n"
        exit 1
    else
        printf "${GREEN}✓ Video save path is writable${NC}\n"
    fi
    
    if [[ ! -w "$image_save_path" ]]; then
        printf "${RED}ERROR: No write permission for image save path: ${image_save_path}${NC}\n"
        printf "${YELLOW}Please check directory permissions${NC}\n"
        exit 1
    else
        printf "${GREEN}✓ Image save path is writable${NC}\n"
    fi
    
    printf "${GREEN}All save paths validated successfully${NC}\n"
}

# Configuration sync function for Wan2GP save paths
sync_save_paths() {
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Synchronizing save path configurations...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    local save_path_file="${SCRIPT_DIR}/save_path.json"
    local wgp_config_file="${WAN2GP_DIR}/wgp_config.json"
    local save_path=""
    local image_save_path=""
    local config_source=""
    
    # Only sync if wgp_config.json exists (after first run)
    if [[ ! -f "$wgp_config_file" ]]; then
        printf "${BLUE}Wan2GP config file not found - will be created on first run${NC}\n"
        printf "${BLUE}Save path configuration will be applied on subsequent runs${NC}\n"
        return
    fi
    
    # Try to read from save_path.json first
    if [[ -f "$save_path_file" ]]; then
        printf "${BLUE}Reading save paths from ${save_path_file}...${NC}\n"
        
        # Activate conda environment for python access
        eval "$("${CONDA_EXE}" shell.bash hook)" 2>/dev/null
        conda activate "${ENV_NAME}" 2>/dev/null
        
        # Extract values using python
        save_path=$(python -c "
import json
try:
    with open('${save_path_file}', 'r') as f:
        data = json.load(f)
    print(data.get('save_path', ''))
except Exception as e:
    print('')
" 2>/dev/null)
        
        image_save_path=$(python -c "
import json
try:
    with open('${save_path_file}', 'r') as f:
        data = json.load(f)
    print(data.get('image_save_path', ''))
except Exception as e:
    print('')
" 2>/dev/null)
        
        if [[ -n "$save_path" ]] && [[ -n "$image_save_path" ]]; then
            config_source="save_path.json"
            printf "${GREEN}Successfully read paths from save_path.json${NC}\n"
        else
            printf "${YELLOW}Warning: Could not read valid paths from save_path.json${NC}\n"
        fi
    fi
    
    # Fall back to script variables if save_path.json failed or doesn't exist
    if [[ -z "$save_path" ]] || [[ -z "$image_save_path" ]]; then
        if [[ -n "$SCRIPT_SAVE_PATH" ]] && [[ -n "$SCRIPT_IMAGE_SAVE_PATH" ]]; then
            save_path="$SCRIPT_SAVE_PATH"
            image_save_path="$SCRIPT_IMAGE_SAVE_PATH"
            config_source="script variables"
            printf "${BLUE}Using save paths from script variables${NC}\n"
        else
            printf "${GREEN}No save paths configured - leaving wgp_config.json unchanged${NC}\n"
            printf "${BLUE}Wan2GP will use its own default save locations${NC}\n"
            return
        fi
    fi
    
    printf "${GREEN}Save paths from ${config_source}:${NC}\n"
    printf "  save_path: ${save_path}\n"
    printf "  image_save_path: ${image_save_path}\n"
    
    # Read current values from wgp_config.json
    local current_save_path=$(python -c "
import json
try:
    with open('${wgp_config_file}', 'r') as f:
        data = json.load(f)
    print(data.get('save_path', ''))
except Exception as e:
    print('')
" 2>/dev/null)
    
    local current_image_save_path=$(python -c "
import json
try:
    with open('${wgp_config_file}', 'r') as f:
        data = json.load(f)
    print(data.get('image_save_path', ''))
except Exception as e:
    print('')
" 2>/dev/null)
    
    printf "${BLUE}Current paths in wgp_config.json:${NC}\n"
    printf "  save_path: ${current_save_path}\n"
    printf "  image_save_path: ${current_image_save_path}\n"
    
    # Check if sync is needed
    if [[ "$save_path" == "$current_save_path" ]] && [[ "$image_save_path" == "$current_image_save_path" ]]; then
        printf "${GREEN}✓ Configurations are already synchronized${NC}\n"
        return
    fi
    
    printf "${YELLOW}Configurations differ - updating wgp_config.json...${NC}\n"
    
    # Update wgp_config.json with new paths
    python -c "
import json
try:
    with open('${wgp_config_file}', 'r') as f:
        config = json.load(f)
    
    config['save_path'] = '${save_path}'
    config['image_save_path'] = '${image_save_path}'
    
    with open('${wgp_config_file}', 'w') as f:
        json.dump(config, f, indent=4)
    
    print('SUCCESS')
except Exception as e:
    print(f'ERROR: {e}')
"
    
    local result=$(python -c "
import json
try:
    with open('${wgp_config_file}', 'r') as f:
        config = json.load(f)
    
    config['save_path'] = '${save_path}'
    config['image_save_path'] = '${image_save_path}'
    
    with open('${wgp_config_file}', 'w') as f:
        json.dump(config, f, indent=4)
    
    print('SUCCESS')
except Exception as e:
    print(f'ERROR: {e}')
" 2>/dev/null)
    
    if [[ "$result" == "SUCCESS" ]]; then
        printf "${GREEN}✓ Successfully synchronized save paths in wgp_config.json${NC}\n"
        
        # Create directories if they don't exist
        printf "${BLUE}Ensuring save directories exist...${NC}\n"
        mkdir -p "$save_path" 2>/dev/null && printf "${GREEN}✓ Video save directory: ${save_path}${NC}\n" || printf "${YELLOW}Warning: Could not create video directory${NC}\n"
        mkdir -p "$image_save_path" 2>/dev/null && printf "${GREEN}✓ Image save directory: ${image_save_path}${NC}\n" || printf "${YELLOW}Warning: Could not create image directory${NC}\n"
    else
        printf "${RED}✗ Failed to update wgp_config.json: ${result}${NC}\n"
        printf "${YELLOW}Please check file permissions and try again${NC}\n"
    fi
}

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
    # Only clean custom temp directory, not system default
    if [[ -n "$TEMP_CACHE_DIR" ]] && [[ -n "$LOCAL_TEMP_DIR" ]] && [[ -d "${LOCAL_TEMP_DIR}" ]]; then
        CACHE_SIZE=$(du -sm "${LOCAL_TEMP_DIR}" 2>/dev/null | cut -f1 || echo "0")
        if [[ $CACHE_SIZE -gt $CACHE_SIZE_THRESHOLD ]] || [[ "$FORCE_CACHE_CLEANUP" == "true" ]]; then
            if [[ "$FORCE_CACHE_CLEANUP" == "true" ]]; then
                printf "${YELLOW}Force cleaning custom temp cache (${CACHE_SIZE}MB)...${NC}\n"
            else
                printf "${YELLOW}Custom temp cache is ${CACHE_SIZE}MB (threshold: ${CACHE_SIZE_THRESHOLD}MB), cleaning up...${NC}\n"
            fi
            rm -rf "${LOCAL_TEMP_DIR}"/* 2>/dev/null || printf "${YELLOW}Warning: Could not clean custom cache${NC}\n"
        else
            printf "${GREEN}Custom temp cache size: ${CACHE_SIZE}MB (threshold: ${CACHE_SIZE_THRESHOLD}MB, keeping)${NC}\n"
        fi
    elif [[ -z "$TEMP_CACHE_DIR" ]]; then
        printf "${BLUE}No custom temp directory configured - skipping custom cache cleanup${NC}\n"
    fi
    
    # Clean up Python cache (only if auto cleanup is enabled or forced)
    if [[ "$AUTO_CACHE_CLEANUP" == "true" ]] || [[ "$FORCE_CACHE_CLEANUP" == "true" ]]; then
        if [[ -d "${WAN2GP_DIR}/__pycache__" ]]; then
            printf "${YELLOW}Cleaning Python cache...${NC}\n"
            find "${WAN2GP_DIR}" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
            find "${WAN2GP_DIR}" -name "*.pyc" -delete 2>/dev/null || true
        fi
    fi
    
    printf "${GREEN}Cache cleanup completed${NC}\n"
}

# Set up cleanup trap for script exit
cleanup_on_exit() {
    printf "\n${YELLOW}Wan2GP is shutting down...${NC}\n"
    cleanup_cache
    printf "${GREEN}Cleanup completed. Goodbye!${NC}\n"
}

# Register cleanup function to run on script exit
trap cleanup_on_exit EXIT INT TERM

# Activate conda environment for the main application
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Activating conda environment for Wan2GP...${NC}\n"
printf "%s\n" "${delimiter}"

eval "$("${CONDA_EXE}" shell.bash hook)"
conda activate "${ENV_NAME}"

if [[ $? -ne 0 ]]; then
    printf "\n${RED}ERROR: Failed to activate conda environment '${ENV_NAME}'${NC}\n"
    exit 1
fi

# Validate save paths before proceeding
validate_save_paths

# Perform startup cache cleanup
printf "\n%s\n" "${delimiter}"
if [[ "$AUTO_CACHE_CLEANUP" == "true" ]] || [[ "$FORCE_CACHE_CLEANUP" == "true" ]]; then
    printf "${GREEN}Performing startup cache cleanup...${NC}\n"
else
    printf "${BLUE}Startup cache cleanup disabled (AUTO_CACHE_CLEANUP=false)${NC}\n"
fi
printf "%s\n" "${delimiter}"
cleanup_cache

# Synchronize save path configurations
sync_save_paths

# Launch the application
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Launching Wan2GP AI Video Generator...${NC}\n"
printf "${BLUE}Using conda environment: ${CONDA_DEFAULT_ENV}${NC}\n"
printf "${BLUE}Python: $(which python)${NC}\n"
printf "${BLUE}Working directory: ${WAN2GP_DIR}${NC}\n"
printf "%s\n" "${delimiter}"

# Detect actual SageAttention version installed
detect_sageattention_version() {
    local installed_version=$("${python_cmd}" -c "
try:
    import pip
    packages = {pkg.key: pkg.version for pkg in pip.get_installed_distributions()}
    if 'sageattention' in packages:
        print(packages['sageattention'])
    else:
        print('not_installed')
except:
    # Fallback for newer pip versions
    import subprocess
    result = subprocess.run(['pip', 'list'], capture_output=True, text=True)
    for line in result.stdout.split('\n'):
        if line.startswith('sageattention'):
            print(line.split()[1])
            break
    else:
        print('not_installed')
" 2>/dev/null || echo "not_installed")
    echo "$installed_version"
}

# Prepare TCMalloc
prepare_tcmalloc

# Set python command to use activated environment
python_cmd="python"

# Disable sentry logging (if configured)
if [[ "$DISABLE_ERROR_REPORTING" == "true" ]]; then
    export ERROR_REPORTING=FALSE
fi

# Set temporary directory only if custom path is configured
if [[ -n "$TEMP_CACHE_DIR" ]] && [[ -n "$LOCAL_TEMP_DIR" ]]; then
    # TMPDIR is the standard Unix environment variable that Python's tempfile module respects
    export TMPDIR="${LOCAL_TEMP_DIR}"
    mkdir -p "${LOCAL_TEMP_DIR}"
    printf "${BLUE}Using custom temporary files directory (TMPDIR): ${TMPDIR}${NC}\n"
    printf "${BLUE}This will redirect Gradio cache from default location to custom directory${NC}\n"
else
    printf "${GREEN}No custom temp directory configured - letting system/app choose default location${NC}\n"
    printf "${BLUE}Application will use its own preferred temp directory${NC}\n"
fi

# Parse command line arguments to determine which mode to run
MODE="i2v"  # default to image-to-video
ENABLE_TCMALLOC="$DEFAULT_ENABLE_TCMALLOC"  # Default from configuration
FORCE_CACHE_CLEANUP=false  # Force full cache cleanup
# Note: REBUILD_ENV, DISABLE_GIT_UPDATE, and SAGE_VERSION already parsed early
for arg in "$@"; do
    case $arg in
        --t2v)
            MODE="t2v"
            shift
            ;;
        --disable-tcmalloc)
            ENABLE_TCMALLOC=false
            shift
            ;;
        --sage3)
            # Already handled in early parsing
            shift
            ;;
        --sage2)
            # Already handled in early parsing
            shift
            ;;
        --clean-cache)
            FORCE_CACHE_CLEANUP=true
            shift
            ;;
        --rebuild-env)
            # Already handled in early parsing
            shift
            ;;
        --no-git-update)
            # Already handled in early parsing
            shift
            ;;
        --help|-h)
            printf "${GREEN}Wan2GP Usage:${NC}\n"
            printf "  Default (no args): Image-to-video mode with SageAttention 2.2.0\n"
            printf "  --t2v: Text-to-video mode\n"
            printf "\n${GREEN}SageAttention Options:${NC}\n"
            printf "  --sage2: Use SageAttention 2.2.0 (default, recommended for most users)\n"
            printf "           Repository: GitHub (thu-ml/SageAttention)\n"
            printf "           Compatible with: RTX 3060/3090, RTX 4060/4090, A100, H100, RTX 5090\n"
            printf "           Provides 2-5x speedup with stable performance\n"
            printf "           Requirements: Python >=3.9, PyTorch >=2.0, CUDA >=12.0\n"
            printf "  --sage3: Use SageAttention3 (microscaling FP4 for Blackwell GPUs)\n"
            printf "           Repository: HuggingFace (jt-zhang/SageAttention3) - may be GATED\n"
            printf "           Optimized for: RTX 5070/5080/5090 (Blackwell architecture)\n"
            printf "           Features: FP4 Tensor Cores with up to 5x speedup\n"
            printf "           Requirements: Python >=3.13, PyTorch >=2.8.0, CUDA >=12.8\n"
            printf "           Note: Requires HuggingFace access approval if repository is gated\n"
            printf "\n${GREEN}Other Options:${NC}\n"
            printf "  --disable-tcmalloc: Disable TCMalloc (if you experience library conflicts)\n"
            printf "  --clean-cache: Force full cache cleanup on startup\n"
            printf "  --rebuild-env: Remove and rebuild the conda environment\n"
            printf "  --no-git-update: Skip git update for this run (overrides AUTO_GIT_UPDATE)\n"
            printf "  --help, -h: Show this help\n"
            printf "\n${GREEN}Repository Selection (first-time setup only):${NC}\n"
            printf "  On first run, you'll be prompted to choose between:\n"
            printf "  1) Official Repository (deepbeepmeep/Wan2GP) - Standard version\n"
            printf "  2) Custom Fork - Includes WAN2.2-14B-Rapid-AllInOne Mega-v3 support\n"
            printf "\n${GREEN}Configuration:${NC}\n"
            printf "  Edit wan2gp-config.sh to customize settings:\n"
            printf "  • DEFAULT_SAGE_VERSION: Set default SageAttention version (2 or 3)\n"
            printf "                         2 = SageAttention 2.2.0 from GitHub (recommended)\n"
            printf "                         3 = SageAttention3 from HuggingFace (requires Python 3.13)\n"
            printf "  • DEFAULT_ENABLE_TCMALLOC: Enable TCMalloc for better memory (default: true)\n"
            printf "  • DEFAULT_SERVER_PORT: Default Gradio server port (default: 7862)\n"
            printf "  • TEMP_CACHE_DIR: Custom temp cache directory (empty = system default)\n"
            printf "  • AUTO_CACHE_CLEANUP: Enable/disable automatic cache cleanup (default: false)\n"
            printf "  • AUTO_GIT_UPDATE: Enable/disable automatic git updates (default: false)\n"
            printf "  • CACHE_SIZE_THRESHOLD: Cache size in MB before cleanup (default: 100)\n"
            printf "  • SCRIPT_SAVE_PATH: Default video save path (fallback if save_path.json fails)\n"
            printf "  • SCRIPT_IMAGE_SAVE_PATH: Default image save path (fallback if save_path.json fails)\n"
            printf "  • CONDA_EXE: Path to conda executable\n"
            printf "  • Repository URLs and branches for both official and fork versions\n"
            printf "  • SageAttention compilation settings and GPU configurations\n"
            printf "\n${GREEN}All other arguments are passed to wgp.py${NC}\n"
            exit 0
            ;;
    esac
done

# Detect installed SageAttention version
INSTALLED_SAGE_VERSION=$(detect_sageattention_version)

# Launch the application with all passed arguments
if [[ "$SAGE_VERSION" == "3" ]]; then
    if [[ "$INSTALLED_SAGE_VERSION" == "not_installed" ]]; then
        printf "${RED}WARNING: SageAttention is not installed!${NC}\n"
        printf "${YELLOW}Wan2GP will run with standard attention (slower)${NC}\n"
        printf "${BLUE}To install SageAttention, use: --rebuild-env flag${NC}\n"
    elif [[ ! "$INSTALLED_SAGE_VERSION" =~ ^3\. ]]; then
        printf "${YELLOW}Note: SageAttention3 not installed (version ${INSTALLED_SAGE_VERSION} found)${NC}\n"
        printf "${GREEN}Starting Wan2GP in ${MODE} mode with SageAttention ${INSTALLED_SAGE_VERSION}...${NC}\n"
        printf "${BLUE}To install SageAttention3: Upgrade to Python 3.13 and use --rebuild-env${NC}\n"
    else
        printf "${GREEN}Starting Wan2GP in ${MODE} mode with SageAttention3 ${INSTALLED_SAGE_VERSION}!${NC}\n"
        printf "${BLUE}Using microscaling FP4 attention optimized for Blackwell GPUs${NC}\n"
    fi
else
    if [[ "$INSTALLED_SAGE_VERSION" == "not_installed" ]]; then
        printf "${RED}WARNING: SageAttention is not installed!${NC}\n"
        printf "${YELLOW}Wan2GP will run with standard attention (slower)${NC}\n"
    elif [[ "$INSTALLED_SAGE_VERSION" =~ ^2\. ]]; then
        printf "${GREEN}Starting Wan2GP in ${MODE} mode with SageAttention ${INSTALLED_SAGE_VERSION}...${NC}\n"
        printf "${BLUE}Note: SageAttention 2.2.0 provides 2-5x speedup with low-bit attention${NC}\n"
    else
        printf "${GREEN}Starting Wan2GP in ${MODE} mode with SageAttention ${INSTALLED_SAGE_VERSION}...${NC}\n"
    fi
fi

# LoRA usage tip for Wan 2.2 models
printf "${BLUE}LoRA Tip: For Wan 2.2 High/Low noise models, use semicolon syntax:${NC}\n"
printf "${BLUE}  Example: '1;0 0;1' (High LoRA only in phase 1, Low LoRA only in phase 2)${NC}\n"

# Check if server-port is already specified in arguments
if [[ ! "$*" =~ --server-port ]]; then
    # Add default port if not specified
    DEFAULT_PORT="--server-port $DEFAULT_SERVER_PORT"
else
    DEFAULT_PORT=""
fi

if [[ "$MODE" == "t2v" ]]; then
    "${python_cmd}" -u wgp.py $DEFAULT_PORT "$@"
else
    # Let the configuration file determine the default i2v model (should be i2v_2_2)
    "${python_cmd}" -u wgp.py $DEFAULT_PORT "$@"
fi

printf "\n%s\n" "${delimiter}"
printf "${GREEN}Wan2GP session ended${NC}\n"
printf "%s\n" "${delimiter}"
