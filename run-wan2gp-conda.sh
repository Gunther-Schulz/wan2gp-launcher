#!/bin/bash
#########################################################
# Wan2GP - Conda Environment Runner
# This script activates the conda environment and runs Wan2GP
# without trying to install dependencies itself
#
# Path Validation:
#   The script validates all configured paths before starting:
#   - TEMP_CACHE_DIR: Must exist and be writable (exit if not)
#   - save_path (from save_path.json): Must exist and be writable (exit if not)
#   - image_save_path (from save_path.json): Must exist and be writable (exit if not)
#   This prevents startup with invalid paths.
#########################################################


#########################################################
# Configuration Loading
#########################################################

# Get the directory where this script is located (needed for config file path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared library with common functions
if [[ -f "${SCRIPT_DIR}/launcher-common.sh" ]]; then
    source "${SCRIPT_DIR}/launcher-common.sh"
else
    echo "ERROR: launcher-common.sh not found in ${SCRIPT_DIR}"
    echo "This file is required for the launcher to function properly."
    exit 1
fi

# Load configuration from external config file
CONFIG_FILE="${SCRIPT_DIR}/wan2gp-config.sh"

# Note: Color definitions and constants are now in launcher-common.sh

# Set fallback defaults in case config file is missing or incomplete
# This handles both missing config file AND empty values in existing config file
set_default_config() {
    # Cache and cleanup configuration
    [[ -z "$AUTO_CACHE_CLEANUP" ]] && AUTO_CACHE_CLEANUP=false
    [[ -z "$CACHE_SIZE_THRESHOLD" ]] && CACHE_SIZE_THRESHOLD=100
    
    # Git update configuration  
    [[ -z "$AUTO_GIT_UPDATE" ]] && AUTO_GIT_UPDATE=true
    
    # Package verification configuration
    [[ -z "$AUTO_CHECK_PACKAGES" ]] && AUTO_CHECK_PACKAGES=true
    [[ -z "$AUTO_FIX_PACKAGE_MISMATCHES" ]] && AUTO_FIX_PACKAGE_MISMATCHES=true
    
    # System paths (empty TEMP_CACHE_DIR means use system default)
    [[ -z "$CONDA_EXE" ]] && CONDA_EXE="/opt/miniconda3/bin/conda"
    
    # Save path configuration - always let app use its own defaults
    # Only set paths if explicitly configured in config file
    # Empty or missing values = let the Wan2GP app decide everything
    
    # Advanced configuration
    [[ -z "$DEFAULT_SAGE_VERSION" ]] && DEFAULT_SAGE_VERSION="auto"
    [[ -z "$AUTO_UPGRADE_SAGE" ]] && AUTO_UPGRADE_SAGE=false
    [[ -z "$DEFAULT_ENABLE_TCMALLOC" ]] && DEFAULT_ENABLE_TCMALLOC=true
    [[ -z "$DEFAULT_SERVER_PORT" ]] && DEFAULT_SERVER_PORT="7862"
    
    # Attention package installation configuration
    [[ -z "$INSTALL_FLASH_ATTENTION" ]] && INSTALL_FLASH_ATTENTION=false
    
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

# Note: Helper functions and constants now loaded from launcher-common.sh:
# - calculate_parallel_jobs(), set_parallel_build_env()
# - uninstall_sageattention(), activate_conda_env()
# - SAGE_REPO_URL, SAGE_*_DIR, SAGE_*_LOG paths
# - Color codes (RED, GREEN, BLUE, YELLOW, NC)

# Early parsing of flags that need to be processed before environment checks
REBUILD_ENV=false
DISABLE_GIT_UPDATE=false
SKIP_PACKAGE_CHECK=false
SAGE_VERSION="$DEFAULT_SAGE_VERSION"  # Start with config value: "auto", "2", or "3"
SAGE_VERSION_EXPLICIT=false  # Track if user explicitly set version via flag
for arg in "$@"; do
    case $arg in
        --rebuild-env)
            REBUILD_ENV=true
            ;;
        --no-git-update)
            DISABLE_GIT_UPDATE=true
            ;;
        --skip-package-check)
            SKIP_PACKAGE_CHECK=true
            ;;
        --sage3)
            SAGE_VERSION="3"
            SAGE_VERSION_EXPLICIT=true
            ;;
        --sage2)
            SAGE_VERSION="2"
            SAGE_VERSION_EXPLICIT=true
            ;;
    esac
done

# Note: Colors (RED, GREEN, BLUE, YELLOW, NC) are defined in launcher-common.sh
# Note: Delimiter will be added to launcher-common.sh

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
    printf "   - Enhanced fork with additional features\n"
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
                REPO_NAME="Custom Fork (Enhanced)"
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
    
    # Set up upstream remote for forks
    if [[ "$choice" == "2" ]]; then
        cd "${WAN2GP_DIR}"
        printf "${BLUE}Setting up upstream remote for fork...${NC}\n"
        git remote add upstream "${OFFICIAL_REPO_URL}" 2>/dev/null || {
            printf "${YELLOW}Upstream remote already exists or could not be added${NC}\n"
        }
        printf "${GREEN}✓ Added upstream remote: ${OFFICIAL_REPO_URL}${NC}\n"
        cd - > /dev/null
        
        printf "\n${GREEN}Additional Features Available:${NC}\n"
        printf "${BLUE}• Enhanced fork with additional features and improvements${NC}\n"
    fi
fi

# Detect conda installation using common library function
detect_conda "wan2gp-config.sh"

# Environment name (from configuration)
ENV_NAME="$CONDA_ENV_NAME"

# Handle environment rebuild if requested
if [[ "$REBUILD_ENV" == "true" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${YELLOW}Rebuild environment requested - removing existing conda environment...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Ask for confirmation before proceeding
    printf "${RED}WARNING: This will remove the existing conda environment '${ENV_NAME}' and all installed packages!${NC}\n"
    printf "${YELLOW}This action cannot be undone.${NC}\n"
    printf "\n${YELLOW}Do you want to continue? [y/N]: ${NC}"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        printf "${BLUE}Rebuild cancelled by user. Exiting...${NC}\n"
        exit 0
    fi
    
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
        
        # Verify PyTorch is installed before attempting Flash Attention
        printf "${BLUE}Verifying PyTorch installation...${NC}\n"
        PYTORCH_CHECK=$(python -c "import torch; print(torch.__version__)" 2>/dev/null)
        if [[ -z "$PYTORCH_CHECK" ]]; then
            printf "${RED}ERROR: PyTorch not found! Flash Attention and SageAttention require PyTorch.${NC}\n"
            printf "${YELLOW}Please check that requirements.txt was installed correctly.${NC}\n"
            printf "${YELLOW}Skipping attention optimization packages.${NC}\n"
        else
            printf "${GREEN}PyTorch ${PYTORCH_CHECK} detected${NC}\n"
            
            # Install Flash Attention if enabled in config (optional fallback, SageAttention is preferred)
            if [[ "$INSTALL_FLASH_ATTENTION" == "true" ]]; then
                printf "${BLUE}Installing Flash Attention (fallback attention optimization)...${NC}\n"
                printf "${BLUE}Forcing source compilation to match installed PyTorch version${NC}\n"
                printf "${BLUE}Using --no-build-isolation --no-binary to ensure compilation from source${NC}\n"
                pip install flash-attn --no-build-isolation --no-binary flash-attn --force-reinstall --no-cache-dir
                if [[ $? -eq 0 ]]; then
                    printf "${GREEN}Flash Attention installed successfully${NC}\n"
                else
                    printf "${YELLOW}Warning: Failed to install Flash Attention (this is normal on some systems)${NC}\n"
                    printf "${YELLOW}Flash Attention requires CUDA toolkit and may not work on all GPUs${NC}\n"
                fi
            else
                printf "${BLUE}Flash Attention installation skipped (INSTALL_FLASH_ATTENTION=false)${NC}\n"
                printf "${BLUE}SageAttention will be used as primary attention optimization${NC}\n"
            fi
        fi
        
        # Install SageAttention (compile from source for best performance)
        # Only proceed if PyTorch verification passed and not disabled
        if [[ -z "$PYTORCH_CHECK" ]]; then
            printf "${YELLOW}Skipping SageAttention installation (PyTorch not available)${NC}\n"
        elif [[ "$DEFAULT_SAGE_VERSION" == "none" ]]; then
            printf "${BLUE}SageAttention installation disabled (DEFAULT_SAGE_VERSION=\"none\")${NC}\n"
            printf "${YELLOW}Wan2GP will use standard PyTorch attention (slower)${NC}\n"
        else
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
            
            # Use common SageAttention installation function
            # Check Python version for SageAttention3
            if [[ "$SAGE_VERSION" == "3" ]]; then
                PYTHON_VERSION=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
                printf "${BLUE}Current Python version: ${PYTHON_VERSION}${NC}\n"
                if ! check_python_sage3_support; then
                    printf "${RED}ERROR: SageAttention3 requires Python 3.13 or higher${NC}\n"
                    printf "${YELLOW}Current Python version: ${PYTHON_VERSION}${NC}\n"
                    printf "${YELLOW}Please update environment-wan2gp.yml to use Python 3.13 for SageAttention3${NC}\n"
                    printf "${YELLOW}Falling back to SageAttention 2.2.0 installation...${NC}\n"
                    SAGE_VERSION="2"
                else
                    printf "${BLUE}Installing SageAttention3 from source (Blackwell FP4 attention)...${NC}\n"
                    printf "${YELLOW}Requirements: Python >=3.13, PyTorch >=2.8.0, CUDA >=12.8${NC}\n"
                fi
            fi
            
            # Set CUDA_HOME if not already set
            export CUDA_HOME="${CUDA_HOME:-${CONDA_PREFIX}}"
            
            # Use common installation function with auto GPU detection for v2, simple for v3
            if [[ "$SAGE_VERSION" == "3" ]]; then
                install_sage_from_source "$WAN2GP_DIR" "$SAGE3_INITIAL_LOG" "3" "simple"
            else
                install_sage_from_source "$WAN2GP_DIR" "$SAGE_INITIAL_LOG" "2" "auto"
            fi
        fi
        fi  # End of PyTorch check for SageAttention installation
        

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

    # Check if we need to switch remotes based on config
    CURRENT_ORIGIN=$(git remote get-url origin 2>/dev/null || echo "")
    
    # Determine which repo should be used based on current remote or config preference
    # If current remote matches custom repo, use custom; otherwise use official
    if [[ "$CURRENT_ORIGIN" == *"Gunther-Schulz/Wan2GP"* ]] || [[ "$CURRENT_ORIGIN" == "$CUSTOM_REPO_URL" ]]; then
        # Currently using custom fork
        EXPECTED_REPO="$CUSTOM_REPO_URL"
        TARGET_BRANCH="$CUSTOM_REPO_BRANCH"
        USING_FORK=true
    else
        # Currently using or should use official repo
        EXPECTED_REPO="$OFFICIAL_REPO_URL"
        TARGET_BRANCH="$OFFICIAL_REPO_BRANCH"
        if [[ -z "$TARGET_BRANCH" ]]; then
            TARGET_BRANCH="main"
        fi
        USING_FORK=false
    fi
    
    # Switch origin remote if it doesn't match expected repo
    if [[ -n "$CURRENT_ORIGIN" ]] && [[ "$CURRENT_ORIGIN" != "$EXPECTED_REPO" ]]; then
        printf "${BLUE}Config changed: switching origin remote to match config...${NC}\n"
        printf "${YELLOW}Old origin: ${CURRENT_ORIGIN}${NC}\n"
        printf "${GREEN}New origin: ${EXPECTED_REPO}${NC}\n"
        git remote set-url origin "${EXPECTED_REPO}" 2>/dev/null || {
            printf "${YELLOW}Warning: Could not update origin remote${NC}\n"
        }
        # Fetch from new origin
        printf "${BLUE}Fetching from new origin...${NC}\n"
        git fetch origin "${TARGET_BRANCH}" 2>/dev/null || true
        # Update USING_FORK flag after switch
        if [[ "$EXPECTED_REPO" == "$CUSTOM_REPO_URL" ]]; then
            USING_FORK=true
        else
            USING_FORK=false
        fi
    fi

    # Store current commit hash
    CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

    # Always switch to the target branch from config
    printf "${BLUE}Switching to ${TARGET_BRANCH} branch (from config)...${NC}\n"
    git checkout "${TARGET_BRANCH}" 2>/dev/null || {
        # Branch doesn't exist locally, try to create it from upstream or origin
        if git remote get-url upstream >/dev/null 2>&1; then
            printf "${BLUE}Creating ${TARGET_BRANCH} branch from upstream...${NC}\n"
            git checkout -b "${TARGET_BRANCH}" "upstream/${TARGET_BRANCH}" 2>/dev/null || {
                printf "${YELLOW}Could not create from upstream, trying origin...${NC}\n"
                git checkout -b "${TARGET_BRANCH}" "origin/${TARGET_BRANCH}" 2>/dev/null || {
                    printf "${RED}ERROR: Could not switch to or create ${TARGET_BRANCH} branch${NC}\n"
                }
            }
        else
            printf "${BLUE}Creating ${TARGET_BRANCH} branch from origin...${NC}\n"
            git checkout -b "${TARGET_BRANCH}" "origin/${TARGET_BRANCH}" 2>/dev/null || {
                printf "${RED}ERROR: Could not switch to or create ${TARGET_BRANCH} branch${NC}\n"
            }
        fi
    }

    # Pull latest changes from origin (the configured repo - fork or official)
    printf "${BLUE}Pulling latest changes from git repository...${NC}\n"
    printf "${BLUE}Current branch: ${TARGET_BRANCH}${NC}\n"
    printf "${BLUE}Pulling from origin ${TARGET_BRANCH}...${NC}\n"
    git pull origin "${TARGET_BRANCH}" 2>&1 || {
        # Fallback to main/master for official repo only (custom forks use explicit branch names)
        if [[ "$USING_FORK" == "false" ]]; then
            printf "${YELLOW}Could not pull ${TARGET_BRANCH}, trying main/master...${NC}\n"
            git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || {
                printf "${YELLOW}Warning: Could not pull from standard branches${NC}\n"
            }
        else
            printf "${YELLOW}Warning: Could not pull from origin ${TARGET_BRANCH}${NC}\n"
        fi
    }
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

    # Check if requirements.txt changed between old and new commit (handles both updates and branch switches)
    if git diff --name-only "$CURRENT_COMMIT" HEAD | grep -q "requirements.txt"; then
        printf "${YELLOW}Requirements file updated! Reinstalling pip packages...${NC}\n"
        # Ensure conda environment is activated for pip updates
        activate_conda_env
        pip install -r requirements.txt --upgrade
        if [[ $? -eq 0 ]]; then
            printf "${GREEN}Requirements updated successfully!${NC}\n"
        else
            printf "${RED}Warning: Failed to update some requirements${NC}\n"
        fi
        
        # Also update attention packages when requirements change
        if [[ "$INSTALL_FLASH_ATTENTION" == "true" ]]; then
            # Uninstall flash-attn first to ensure clean recompile after PyTorch upgrade
            printf "${BLUE}Updating Flash Attention...${NC}\n"
            printf "${BLUE}Uninstalling flash-attn to recompile against updated PyTorch...${NC}\n"
            pip uninstall flash-attn -y 2>/dev/null || true
            printf "${BLUE}Reinstalling flash-attn from source to match new PyTorch version...${NC}\n"
            pip install flash-attn --no-build-isolation --no-binary flash-attn --force-reinstall --no-cache-dir 2>/dev/null && printf "${GREEN}Flash Attention updated${NC}\n" || printf "${YELLOW}Flash Attention update skipped${NC}\n"
        else
            printf "${BLUE}Flash Attention update skipped (INSTALL_FLASH_ATTENTION=false)${NC}\n"
        fi
        
        # Update SageAttention from source if enabled and CUDA available
        if [[ "$DEFAULT_SAGE_VERSION" == "none" ]]; then
            printf "${BLUE}SageAttention update skipped (DEFAULT_SAGE_VERSION=\"none\")${NC}\n"
        elif command -v nvcc &> /dev/null; then
            printf "${BLUE}Updating SageAttention from source...${NC}\n"
            # Set CUDA_HOME to conda environment to avoid version mismatch
            export CUDA_HOME="${CONDA_PREFIX}"
            SAGE_DIR="$SAGE_UPDATE_DIR"
            
            # Calculate optimal parallel compilation jobs
            PARALLEL_JOBS=$(calculate_parallel_jobs)
            
            # Determine which SageAttention version to update based on runtime SAGE_VERSION
            # Note: At this point in the script, SAGE_VERSION has not been auto-detected yet
            # So we use DEFAULT_SAGE_VERSION but need to handle "auto" properly
            update_sage_version="$DEFAULT_SAGE_VERSION"
            if [[ "$update_sage_version" == "auto" ]]; then
                # Auto-detect based on GPU (same logic as later in script)
                if command -v nvidia-smi &> /dev/null; then
                    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
                    if [[ "$GPU_NAME" =~ RTX[[:space:]]50[7-9]0 ]]; then
                        update_sage_version="3"
                    else
                        update_sage_version="2"
                    fi
                else
                    update_sage_version="2"
                fi
            fi
            
            if [[ "$update_sage_version" == "3" ]]; then
                # Try to update SageAttention3 from official repository
                printf "${BLUE}Attempting to update SageAttention3 from official repository...${NC}\n"
                git clone "$SAGE_REPO_URL" "$SAGE_DIR" 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    cd "$SAGE_DIR/sageattention3_blackwell"
                    set_parallel_build_env "$PARALLEL_JOBS"
                    export TORCH_CUDA_ARCH_LIST="12.0"  # Blackwell
                    uninstall_sageattention "3"
                    python setup.py install 2>/dev/null && printf "${GREEN}SageAttention3 updated from source${NC}\n" || printf "${YELLOW}SageAttention3 source update failed${NC}\n"
                    cd "${WAN2GP_DIR}"
                    rm -rf "$SAGE_DIR"
                else
                    printf "${YELLOW}SageAttention3 update skipped (repository clone failed or offline)${NC}\n"
                fi
            else
                # Update SageAttention 2.2.0 from GitHub
                if git clone "$SAGE_REPO_URL" "$SAGE_DIR" 2>/dev/null; then
                    cd "$SAGE_DIR"
                    set_parallel_build_env "$PARALLEL_JOBS"
                    export TORCH_CUDA_ARCH_LIST="8.0;8.9"  # RTX 30xx/40xx
                    uninstall_sageattention "2"
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
        
        # Detect GPU using common library function (detects 30xx, 40xx, 50xx, etc.)
        detect_gpu
        
        if [[ -n "$GPU_NAME" ]] && [[ "$GPU_NAME" != "unknown" ]]; then
            printf "${BLUE}GPU Model: ${GPU_NAME}${NC}\n"
            if [[ -n "$GPU_COMPUTE_CAP" ]]; then
                printf "${BLUE}Compute Capability: ${GPU_COMPUTE_CAP}${NC}\n"
            fi
            
            # Check if it's a Blackwell GPU (RTX 50xx series) - use SUPPORTS_SAGE3 from detect_gpu()
            if [[ "$SUPPORTS_SAGE3" == "true" ]]; then
                    printf "${YELLOW}═══════════════════════════════════════════════════════════${NC}\n"
                    printf "${GREEN}🚀 Blackwell GPU Detected! (RTX 50-series)${NC}\n"
                    
                    # Handle version selection based on config and flags
                    if [[ "$SAGE_VERSION_EXPLICIT" == "true" ]]; then
                        # User explicitly set version via --sage2 or --sage3
                        if [[ "$SAGE_VERSION" == "3" ]]; then
                            printf "${GREEN}✓ Using SageAttention3 (explicit --sage3 flag)${NC}\n"
                        else
                            printf "${YELLOW}💡 Note: Using SageAttention 2 (explicit --sage2 flag)${NC}\n"
                            printf "${YELLOW}   Your GPU supports SageAttention3 for better performance${NC}\n"
                        fi
                    elif [[ "$SAGE_VERSION" == "auto" ]]; then
                        # Auto-detect: Switch to SageAttention3 for Blackwell
                        SAGE_VERSION="3"
                        printf "${GREEN}✓ Auto-detected: Using SageAttention3 (FP4 Tensor Cores)${NC}\n"
                        printf "${BLUE}   Optimized for Blackwell architecture - up to 5x faster${NC}\n"
                        printf "${BLUE}   Config: DEFAULT_SAGE_VERSION=\"auto\" (adapts per GPU)${NC}\n"
                    elif [[ "$SAGE_VERSION" == "3" ]]; then
                        # Config explicitly set to v3
                        printf "${GREEN}✓ Using SageAttention3 (DEFAULT_SAGE_VERSION=\"3\" in config)${NC}\n"
                    else
                        # Config explicitly set to v2
                        printf "${YELLOW}💡 Note: Using SageAttention 2 (DEFAULT_SAGE_VERSION=\"2\" in config)${NC}\n"
                        printf "${YELLOW}   Your GPU supports SageAttention3 for better performance${NC}\n"
                        printf "${YELLOW}   To auto-detect, set DEFAULT_SAGE_VERSION=\"auto\" in config${NC}\n"
                    fi
                printf "${YELLOW}═══════════════════════════════════════════════════════════${NC}\n"
            else
                # Non-Blackwell GPU: handle auto-detection
                if [[ "$SAGE_VERSION" == "auto" ]] && [[ "$SAGE_VERSION_EXPLICIT" == "false" ]]; then
                    SAGE_VERSION="2"  # Default to v2 for non-Blackwell GPUs
                fi
            fi
        fi
    ;;
    *)
        printf "${YELLOW}GPU detection: Unknown or no discrete GPU detected${NC}\n"
        # Default to SageAttention 2 if auto-detection enabled
        if [[ "$SAGE_VERSION" == "auto" ]] && [[ "$SAGE_VERSION_EXPLICIT" == "false" ]]; then
            SAGE_VERSION="2"
        fi
    ;;
esac

# Final fallback: if SAGE_VERSION is still "auto", default to "2"
if [[ "$SAGE_VERSION" == "auto" ]]; then
    SAGE_VERSION="2"
fi

# Handle "none" option to disable SageAttention
if [[ "$SAGE_VERSION" == "none" ]] && [[ "$SAGE_VERSION_EXPLICIT" == "false" ]]; then
    DISABLE_SAGE=true
    printf "${YELLOW}SageAttention disabled (DEFAULT_SAGE_VERSION=\"none\" in config)${NC}\n"
fi

# Auto-patch SageAttention3 import if using sage3
# This fixes upstream import issue until it's resolved
fix_sage3_import() {
    if [[ "$SAGE_VERSION" != "3" ]]; then
        return 0  # Skip patching if not using sage3
    fi
    
    local attention_file="${WAN2GP_DIR}/shared/attention.py"
    
    if [[ ! -f "$attention_file" ]]; then
        printf "${YELLOW}Warning: attention.py not found at ${attention_file}${NC}\n"
        return 0
    fi
    
    # Check if import is incorrect (using 'sageattn' instead of 'sageattn3')
    if grep -q "from sageattn import sageattn_blackwell as sageattn3" "$attention_file" 2>/dev/null; then
        printf "${YELLOW}Detected incorrect SageAttention3 import - applying auto-patch...${NC}\n"
        
        # Apply the fix using sed
        sed -i 's/from sageattn import sageattn_blackwell as sageattn3/from sageattn3 import sageattn3_blackwell as sageattn3/' "$attention_file"
        
        if [[ $? -eq 0 ]]; then
            printf "${GREEN}✓ SageAttention3 import corrected in attention.py${NC}\n"
            printf "${BLUE}  (This fixes upstream compatibility until official fix is released)${NC}\n"
        else
            printf "${RED}✗ Failed to patch attention.py${NC}\n"
            printf "${YELLOW}  You may need to manually fix the import in ${attention_file}${NC}\n"
        fi
    elif grep -q "from sageattn3 import sageattn3_blackwell as sageattn3" "$attention_file" 2>/dev/null; then
        # Import is already correct (either patched or upstream fixed it)
        printf "${GREEN}✓ SageAttention3 import is correct${NC}\n"
    else
        printf "${YELLOW}Note: SageAttention3 import not found in attention.py (may be commented out)${NC}\n"
    fi
}

# Apply sage3 import fix if needed
if [[ "$SAGE_VERSION" == "3" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Checking SageAttention3 import compatibility...${NC}\n"
    printf "%s\n" "${delimiter}"
    fix_sage3_import
fi

# TCMalloc setup (from original script) - with conda compatibility fix
# Note: prepare_tcmalloc() is now in launcher-common.sh

# Set local temporary directory (define early so cleanup function can use it)
# Only use custom temp directory if explicitly configured
if [[ -n "$TEMP_CACHE_DIR" ]]; then
    LOCAL_TEMP_DIR="$TEMP_CACHE_DIR"
else
    # No custom temp directory configured - let system/app decide
    LOCAL_TEMP_DIR=""
fi

# Comprehensive path validation function
validate_all_paths() {
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Validating configured paths...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    local validation_failed=false
    
    # 1. Validate TEMP_CACHE_DIR if specified (using common library function)
    if ! validate_temp_directory "$LOCAL_TEMP_DIR"; then
        validation_failed=true
    fi
    
    # 2. Validate save paths from save_path.json or script variables
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
            printf "${BLUE}Skipping save path validation - application will choose its own locations${NC}\n"
        fi
    fi
    
    # Validate save paths if configured
    if [[ -n "$save_path" ]] && [[ -n "$image_save_path" ]]; then
        printf "${BLUE}Checking save paths from ${config_source}:${NC}\n"
        printf "  save_path: ${save_path}\n"
        printf "  image_save_path: ${image_save_path}\n"
        
        # Validate video save path
        if [[ ! -d "$save_path" ]]; then
            printf "${RED}ERROR: Video save path does not exist: ${save_path}${NC}\n"
            printf "${YELLOW}Solutions:${NC}\n"
            printf "  1. Create the directory: mkdir -p \"${save_path}\"${NC}\n"
            printf "  2. Update save_path.json with valid path${NC}\n"
            printf "  3. Remove save_path.json to let Wan2GP use defaults${NC}\n"
            printf "  4. If using external/network drive, ensure it's mounted${NC}\n"
            validation_failed=true
        else
            printf "${GREEN}✓ Video save path exists: ${save_path}${NC}\n"
            
            # Test write permissions
            if [[ ! -w "$save_path" ]]; then
                printf "${RED}ERROR: No write permission for video save path: ${save_path}${NC}\n"
                printf "${YELLOW}Please check directory permissions${NC}\n"
                validation_failed=true
            else
                printf "${GREEN}✓ Video save path is writable${NC}\n"
            fi
        fi
        
        # Validate image save path
        if [[ ! -d "$image_save_path" ]]; then
            printf "${RED}ERROR: Image save path does not exist: ${image_save_path}${NC}\n"
            printf "${YELLOW}Solutions:${NC}\n"
            printf "  1. Create the directory: mkdir -p \"${image_save_path}\"${NC}\n"
            printf "  2. Update save_path.json with valid path${NC}\n"
            printf "  3. Remove save_path.json to let Wan2GP use defaults${NC}\n"
            printf "  4. If using veracrypt/external drive, ensure it's mounted${NC}\n"
            validation_failed=true
        else
            printf "${GREEN}✓ Image save path exists: ${image_save_path}${NC}\n"
            
            # Test write permissions
            if [[ ! -w "$image_save_path" ]]; then
                printf "${RED}ERROR: No write permission for image save path: ${image_save_path}${NC}\n"
                printf "${YELLOW}Please check directory permissions${NC}\n"
                validation_failed=true
            else
                printf "${GREEN}✓ Image save path is writable${NC}\n"
            fi
        fi
    fi
    
    # Exit if any validation failed
    if [[ "$validation_failed" == "true" ]]; then
        printf "\n%s\n" "${delimiter}"
        printf "${RED}Path validation failed - cannot start${NC}\n"
        printf "${YELLOW}Please fix the issues above and try again${NC}\n"
        printf "%s\n" "${delimiter}"
        exit 1
    fi
    
    printf "${GREEN}✓ All configured paths validated successfully${NC}\n"
}

# Validation function for save paths (legacy - kept for compatibility)
validate_save_paths() {
    # This function is now handled by validate_all_paths() but kept for compatibility
    # In case any custom scripts call it directly
    printf "${BLUE}Note: Save path validation is now handled by validate_all_paths()${NC}\n"
    return 0
}


# Link wan2gp_content directories into Wan2GP
sync_content_directories() {
    local content_root="${SCRIPT_DIR}/wan2gp_content"
    
    # Initialize structure if it doesn't exist (using common library function)
    if [[ ! -d "$content_root" ]]; then
        printf "\n%s\n" "${delimiter}"
        # Define Wan2GP-specific loras structure
        local lora_subdirs=("wan" "wan_i2v" "wan_1.3B" "wan_5B" "flux" "hunyuan" "hunyuan_i2v" "ltxv" "qwen" "tts")
        init_content_directories "$content_root" "Wan2GP" "${lora_subdirs[@]}"
        printf "%s\n" "${delimiter}"
    fi
    
    # Check again after initialization
    if [[ ! -d "$content_root" ]]; then
        printf "${YELLOW}Warning: Could not create wan2gp_content directory${NC}\n"
        return
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Linking wan2gp_content directories...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    printf "${GREEN}Content root: ${content_root}${NC}\n"
    
    # Link ckpts and finetunes directories (with safety validation)
    link_content_directory "${content_root}/ckpts" "${WAN2GP_DIR}/ckpts" "Checkpoints directory" "${content_root}" "${WAN2GP_DIR}"
    link_content_directory "${content_root}/finetunes" "${WAN2GP_DIR}/finetunes" "Finetunes directory" "${content_root}" "${WAN2GP_DIR}"
    
    # Link each loras subdirectory individually (future-proof: new subdirs automatically handled)
    if [[ -d "${content_root}/loras" ]]; then
        # Ensure target loras directory exists
        mkdir -p "${WAN2GP_DIR}/loras"
        
        # Loop through each subdirectory in wan2gp_content/loras/
        for lora_subdir in "${content_root}/loras"/*; do
            # Skip if not a directory
            [[ ! -d "$lora_subdir" ]] && continue
            
            # Get just the subdirectory name (e.g., "wan", "flux")
            local subdir_name=$(basename "$lora_subdir")
            
            # Skip README.md or other non-directory entries
            [[ "$subdir_name" == "README.md" ]] && continue
            
            # Link individual subdirectory: wan2gp_content/loras/wan → Wan2GP/loras/wan (with safety validation)
            link_content_directory "${lora_subdir}" "${WAN2GP_DIR}/loras/${subdir_name}" "LoRA ${subdir_name} directory" "${content_root}" "${WAN2GP_DIR}"
        done
    else
        printf "${YELLOW}Warning: ${content_root}/loras directory not found${NC}\n"
    fi
    
    printf "${GREEN}✓ Content directories linked${NC}\n"
}

# Configure ckpts directory in wgp_config.json
sync_ckpts_directory() {
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Configuring ckpts directory...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    local wgp_config_file="${WAN2GP_DIR}/wgp_config.json"
    local ckpts_symlink="${WAN2GP_DIR}/ckpts"
    
    # Check if ckpts symlink exists (created by sync_content_directories)
    if [[ ! -L "$ckpts_symlink" ]] && [[ ! -d "$ckpts_symlink" ]]; then
        printf "${YELLOW}Checkpoints directory not linked yet${NC}\n"
        return
    fi
    
    printf "${GREEN}Checkpoints directory is linked${NC}\n"
    
    # Only sync config if wgp_config.json exists (after first run)
    if [[ ! -f "$wgp_config_file" ]]; then
        printf "${BLUE}Wan2GP config file not found - will be configured on first run${NC}\n"
        return
    fi
    
    # Activate conda environment for python access
    activate_conda_env "quiet"
    
    # Check if ckpts directory is at the correct position (first entry)
    # Since we symlink the entire directory, we just need "ckpts" in the config
    local config_status=$(python -c "
import json
try:
    with open('${wgp_config_file}', 'r') as f:
        config = json.load(f)
    
    checkpoints_paths = config.get('checkpoints_paths', [])
    
    # Check if 'ckpts' is already at first position
    if len(checkpoints_paths) > 0 and checkpoints_paths[0] == 'ckpts':
        print('FIRST')
        exit(0)
    
    # Check if present somewhere else
    for i, path in enumerate(checkpoints_paths):
        if path == 'ckpts':
            print(f'FOUND_AT_{i}')
            exit(0)
    
    print('MISSING')
except Exception as e:
    print(f'ERROR: {e}')
" 2>/dev/null)
    
    if [[ "$config_status" == "FIRST" ]]; then
        printf "${GREEN}✓ Checkpoints directory already at first position (downloads will go here)${NC}\n"
        return
    elif [[ "$config_status" == "ERROR"* ]]; then
        printf "${RED}✗ Failed to read wgp_config.json: ${config_status}${NC}\n"
        return
    fi
    
    if [[ "$config_status" == "MISSING" ]]; then
        printf "${YELLOW}Checkpoints directory not found - adding as first entry...${NC}\n"
    else
        printf "${YELLOW}Checkpoints directory found but not first - reordering for auto-downloads...${NC}\n"
    fi
    
    # Add or move ckpts directory to first position in checkpoints_paths
    local result=$(python -c "
import json
try:
    with open('${wgp_config_file}', 'r') as f:
        config = json.load(f)
    
    checkpoints_paths = config.get('checkpoints_paths', [])
    
    # Remove 'ckpts' if present elsewhere
    checkpoints_paths = [p for p in checkpoints_paths if p != 'ckpts']
    
    # Insert 'ckpts' at position 0 (first entry = download location)
    checkpoints_paths.insert(0, 'ckpts')
    
    # Ensure '.' is at the end
    if '.' in checkpoints_paths:
        checkpoints_paths.remove('.')
    checkpoints_paths.append('.')
    
    config['checkpoints_paths'] = checkpoints_paths
    
    with open('${wgp_config_file}', 'w') as f:
        json.dump(config, f, indent=4)
    
    print('SUCCESS')
except Exception as e:
    print(f'ERROR: {e}')
" 2>/dev/null)
    
    if [[ "$result" == "SUCCESS" ]]; then
        printf "${GREEN}✓ Configured checkpoints directory as primary location${NC}\n"
        printf "${GREEN}✓ Auto-downloaded models will go to: ${ckpts_dir}${NC}\n"
        printf "${BLUE}✓ All your custom and auto-downloaded models in one place${NC}\n"
    else
        printf "${RED}✗ Failed to update wgp_config.json: ${result}${NC}\n"
        printf "${YELLOW}Please manually set '${ckpts_dir}' as first entry in checkpoints_paths${NC}\n"
    fi
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

# Note: verify_package_versions() wrapper - uses common library function
verify_package_versions_wrapper() {
    if [[ "$SKIP_PACKAGE_CHECK" == "true" ]]; then
        printf "${BLUE}Package version check skipped (--skip-package-check flag)${NC}\n"
        return 0
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Verifying package versions...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    local requirements_file="${WAN2GP_DIR}/requirements.txt"
    
    # Use common library function
    verify_package_versions "$requirements_file" "${ENV_NAME}" "${CONDA_EXE}" "$AUTO_CHECK_PACKAGES" "$AUTO_FIX_PACKAGE_MISMATCHES"
}

# Note: cleanup_cache() wrapper - uses common library function
cleanup_cache_wrapper() {
    cleanup_cache "${WAN2GP_DIR}" "${LOCAL_TEMP_DIR}" "${CACHE_SIZE_THRESHOLD}" "${AUTO_CACHE_CLEANUP}" "${FORCE_CACHE_CLEANUP}"
}

# Set up cleanup trap for script exit
cleanup_on_exit() {
    printf "\n${YELLOW}Wan2GP is shutting down...${NC}\n"
    cleanup_cache_wrapper
    printf "${GREEN}Cleanup completed. Goodbye!${NC}\n"
}

# Register cleanup function to run on script exit
trap cleanup_on_exit EXIT INT TERM

# Activate conda environment for the main application
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Activating conda environment for Wan2GP...${NC}\n"
printf "%s\n" "${delimiter}"

activate_conda_env

if [[ $? -ne 0 ]]; then
    printf "\n${RED}ERROR: Failed to activate conda environment '${ENV_NAME}'${NC}\n"
    exit 1
fi

# Validate all configured paths before proceeding
validate_all_paths

# Verify package versions match requirements
verify_package_versions_wrapper

# Helper function to compile SageAttention from source (wrapper for common function)
# Usage: install_sageattention_from_source "install" or "upgrade"
# This is a compatibility wrapper that calls the common install_sage_from_source() function
install_sageattention_from_source() {
    local purpose="$1"  # "install" or "upgrade"
    
    # Set CUDA_HOME if not already set
    export CUDA_HOME="${CUDA_HOME:-${CONDA_PREFIX}}"
    
    # Use common installation function with auto GPU detection for v2, simple for v3
    local arch_mode="auto"
    if [[ "$SAGE_VERSION" == "3" ]]; then
        arch_mode="simple"  # Sage3 always uses 12.0
    fi
    
    if install_sage_from_source "$WAN2GP_DIR" "$SAGE_BUILD_LOG" "$SAGE_VERSION" "$arch_mode"; then
        if [[ "$purpose" == "upgrade" ]]; then
            printf "${GREEN}✓ Successfully upgraded SageAttention from source${NC}\n"
            printf "${YELLOW}Please restart Wan2GP to use the new version${NC}\n"
        else
            printf "${GREEN}✓ Successfully installed SageAttention from source${NC}\n"
        fi
        return 0
    else
        return 1
    fi
}

# SageAttention version check and upgrade function
check_sageattention_version() {
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Checking SageAttention version...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Check if SageAttention is actually installed and working (using common function)
    local installed_version=$(detect_sage_version "true")  # Check for sageattn3 too
    
    # Parse the installed version to compare properly
    local installed_sage_ver=""
    if [[ "$installed_version" == "NOT_INSTALLED" ]]; then
        installed_sage_ver="NOT_INSTALLED"
    elif [[ "$installed_version" =~ ^sageattn3: ]]; then
        # SageAttention3 installed
        installed_sage_ver="${installed_version#sageattn3:}"
        printf "${GREEN}✓ SageAttention3 ${installed_sage_ver} is installed${NC}\n"
        printf "${BLUE}(SageAttention3 is the latest version for Blackwell GPUs)${NC}\n"
        return 0  # SageAttention3 is always acceptable (newer experimental version)
    else
        # SageAttention 2.x installed
        installed_sage_ver="$installed_version"
    fi
    
    if [[ "$installed_sage_ver" == "NOT_INSTALLED" ]]; then
        printf "${YELLOW}SageAttention is not installed${NC}\n"
        
        # Display which version will be installed based on SAGE_VERSION
        if [[ "$SAGE_VERSION" == "3" ]]; then
            printf "${BLUE}Will install: SageAttention3 (microscaling FP4 for Blackwell)${NC}\n"
        elif [[ "$SAGE_VERSION" == "2" ]]; then
            printf "${BLUE}Will install: SageAttention 2.2.0 (stable, for RTX 30xx/40xx)${NC}\n"
        fi
        
        if [[ "$AUTO_UPGRADE_SAGE" == "true" ]]; then
            printf "${GREEN}AUTO_UPGRADE_SAGE=true, installing SageAttention from source...${NC}\n"
            install_sageattention_from_source "install"
            if [[ $? -ne 0 ]]; then
                printf "${YELLOW}Continuing without SageAttention (will use standard attention)${NC}\n"
            fi
        else
            printf "${YELLOW}Would you like to install SageAttention from source? [y/N]: ${NC}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                install_sageattention_from_source "install"
                if [[ $? -ne 0 ]]; then
                    printf "${YELLOW}Continuing without SageAttention (will use standard attention)${NC}\n"
                fi
            else
                printf "${BLUE}Skipping SageAttention installation${NC}\n"
            fi
        fi
    elif [[ "$installed_sage_ver" =~ ^1\. ]]; then
        # Old 1.x version detected - offer upgrade
        printf "${YELLOW}Old SageAttention 1.x version detected: ${installed_sage_ver}${NC}\n"
        printf "\n${BLUE}SageAttention 2.x/3.x provides significant improvements over 1.x:${NC}\n"
        printf "  • 2-5x faster attention computation\n"
        printf "  • Per-thread quantization\n"
        printf "  • Outlier smoothing\n"
        printf "  • Better CUDA kernel optimization\n"
        
        if [[ "$AUTO_UPGRADE_SAGE" == "true" ]]; then
            printf "\n${GREEN}AUTO_UPGRADE_SAGE=true, upgrading SageAttention from source...${NC}\n"
            install_sageattention_from_source "upgrade"
            if [[ $? -ne 0 ]]; then
                printf "${YELLOW}Continuing with version ${installed_sage_ver}${NC}\n"
            fi
        else
            printf "\n${YELLOW}Would you like to upgrade SageAttention from source? [y/N]: ${NC}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                install_sageattention_from_source "upgrade"
                if [[ $? -ne 0 ]]; then
                    printf "${YELLOW}Continuing with version ${installed_sage_ver}${NC}\n"
                fi
            else
                printf "${BLUE}Continuing with installed version ${installed_sage_ver}${NC}\n"
                printf "${YELLOW}Note: You may not get optimal performance${NC}\n"
                printf "${YELLOW}To auto-upgrade in future, set AUTO_UPGRADE_SAGE=true in wan2gp-config.sh${NC}\n"
            fi
        fi
    else
        # Version is OK (2.x or 3.x)
        printf "${GREEN}✓ SageAttention ${installed_sage_ver} is installed${NC}\n"
    fi
}

check_sageattention_version

# Perform startup cache cleanup
printf "\n%s\n" "${delimiter}"
if [[ "$AUTO_CACHE_CLEANUP" == "true" ]] || [[ "$FORCE_CACHE_CLEANUP" == "true" ]]; then
    printf "${GREEN}Performing startup cache cleanup...${NC}\n"
else
    printf "${BLUE}Startup cache cleanup disabled (AUTO_CACHE_CLEANUP=false)${NC}\n"
fi
printf "%s\n" "${delimiter}"
cleanup_cache_wrapper

# Synchronize save path configurations
sync_save_paths

# Synchronize ckpts directory configuration (add to wgp_config.json if needed)
sync_ckpts_directory

# Link all wan2gp_content directories (loras, ckpts, finetunes)
sync_content_directories

# Launch the application
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Launching Wan2GP AI Video Generator...${NC}\n"
printf "${BLUE}Using conda environment: ${CONDA_DEFAULT_ENV}${NC}\n"
printf "${BLUE}Python: $(which python)${NC}\n"
printf "${BLUE}Working directory: ${WAN2GP_DIR}${NC}\n"
printf "%s\n" "${delimiter}"

# Detect actual SageAttention version installed
# Returns: "not_installed", "sageattn3:1.0.0", or version number for v2
detect_sageattention_version() {
    local installed_version=$("${python_cmd}" -c "
try:
    import pip
    packages = {pkg.key: pkg.version for pkg in pip.get_installed_distributions()}
    # Check for sageattn3 first (v3 - Blackwell)
    if 'sageattn3' in packages:
        print('sageattn3:' + packages['sageattn3'])
    elif 'sageattention' in packages:
        print(packages['sageattention'])
    else:
        print('not_installed')
except:
    # Fallback for newer pip versions
    import subprocess
    result = subprocess.run(['pip', 'list'], capture_output=True, text=True)
    for line in result.stdout.split('\n'):
        if line.startswith('sageattn3'):
            # Return with package name prefix to identify v3
            print('sageattn3:' + line.split()[1])
            break
        elif line.startswith('sageattention'):
            print(line.split()[1])
            break
    else:
        print('not_installed')
" 2>/dev/null || echo "not_installed")
    echo "$installed_version"
}

# Prepare TCMalloc (using common library function)
prepare_tcmalloc "${ENV_NAME}" "${CONDA_EXE}" "${ENABLE_TCMALLOC}" "${TCMALLOC_GLIBC_THRESHOLD}"

# Set python command to use activated environment
python_cmd="python"

# Set CUDA_HOME to conda environment for JIT compilation of CUDA extensions
# This is critical for libraries like optimum/quanto that compile CUDA code on-the-fly
if [[ -n "${CONDA_PREFIX}" ]]; then
    export CUDA_HOME="${CONDA_PREFIX}"
    # Also set CUDA_PATH for compatibility
    export CUDA_PATH="${CONDA_PREFIX}"
    
    # Conda CUDA toolkit installs headers in targets/x86_64-linux/include
    # Add these paths so compilers can find CUDA headers during JIT compilation
    if [[ -d "${CONDA_PREFIX}/targets/x86_64-linux/include" ]]; then
        # Prepend to existing paths (if any)
        export CPLUS_INCLUDE_PATH="${CONDA_PREFIX}/targets/x86_64-linux/include${CPLUS_INCLUDE_PATH:+:${CPLUS_INCLUDE_PATH}}"
        export C_INCLUDE_PATH="${CONDA_PREFIX}/targets/x86_64-linux/include${C_INCLUDE_PATH:+:${C_INCLUDE_PATH}}"
        # Also add to standard include path
        export CPPFLAGS="-I${CONDA_PREFIX}/targets/x86_64-linux/include ${CPPFLAGS}"
    fi
    
    printf "${BLUE}Setting CUDA_HOME to conda environment: ${CUDA_HOME}${NC}\n"
    printf "${BLUE}Added CUDA include paths for JIT-compiled extensions${NC}\n"
fi

# Detect GPU compute capability and set TORCH_CUDA_ARCH_LIST for JIT compilation
# This prevents errors when libraries like optimum/quanto try to compile CUDA extensions
# Set TORCH_CUDA_ARCH_LIST for JIT compilation using common library function
# detect_gpu() was already called earlier, so GPU_COMPUTE_CAP is set
if [[ -n "$GPU_COMPUTE_CAP" ]] && [[ "$GPU_COMPUTE_CAP" != "" ]]; then
    # Use get_cuda_arch_list with auto-detection to get proper arch list
    # Pass "2" as sage_version (doesn't matter for TORCH_CUDA_ARCH_LIST, just needs a value)
    # Pass "auto" to enable auto-detection from GPU_COMPUTE_CAP
    export TORCH_CUDA_ARCH_LIST=$(get_cuda_arch_list "2" "auto")
    
    # Provide user-friendly GPU name based on compute capability
    gpu_desc=""
    case "$GPU_COMPUTE_CAP" in
        8.0|8.6) gpu_desc="RTX 30xx series (Ampere)" ;;
        8.9) gpu_desc="RTX 40xx series (Ada Lovelace)" ;;
        9.0) gpu_desc="Hopper H100" ;;
        10.*) gpu_desc="Blackwell RTX 50xx" ;;
        12.0|12.*) gpu_desc="Blackwell RTX 5090" ;;
        *) gpu_desc="Unknown GPU" ;;
    esac
    
    printf "${BLUE}Detected GPU compute capability: ${GPU_COMPUTE_CAP} (${gpu_desc})${NC}\n"
    printf "${BLUE}Setting TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST} for CUDA extension compilation${NC}\n"
    if [[ "$GPU_COMPUTE_CAP" == "12.0" ]] || [[ "$GPU_COMPUTE_CAP" =~ ^12\. ]]; then
        printf "${GREEN}✓ Optimized for sm_120 (RTX 5090 Blackwell architecture)${NC}\n"
    fi
else
    # Fallback if GPU detection failed
    export TORCH_CUDA_ARCH_LIST="8.0;8.9"
    printf "${YELLOW}GPU detection failed, defaulting to TORCH_CUDA_ARCH_LIST=8.0;8.9${NC}\n"
fi

# Disable sentry logging (if configured)
if [[ "$DISABLE_ERROR_REPORTING" == "true" ]]; then
    export ERROR_REPORTING=FALSE
fi

# Set temporary directory only if custom path is configured
# Note: Path validation was already done by validate_all_paths()
if [[ -n "$TEMP_CACHE_DIR" ]] && [[ -n "$LOCAL_TEMP_DIR" ]]; then
    # TMPDIR is the standard Unix environment variable that Python's tempfile module respects
    export TMPDIR="${LOCAL_TEMP_DIR}"
    # Create directory if needed (should already exist from validation)
    mkdir -p "${LOCAL_TEMP_DIR}" 2>/dev/null || true
    
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
        --skip-package-check)
            # Already handled in early parsing
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
            printf "           Repository: GitHub (thu-ml/SageAttention/sageattention3_blackwell)\n"
            printf "           Optimized for: RTX 5070/5080/5090 (Blackwell architecture)\n"
            printf "           Features: FP4 Tensor Cores with up to 5x speedup\n"
            printf "           Requirements: Python >=3.13, PyTorch >=2.8.0, CUDA >=12.8\n"
            printf "\n${GREEN}Other Options:${NC}\n"
            printf "  --disable-tcmalloc: Disable TCMalloc (if you experience library conflicts)\n"
            printf "  --clean-cache: Force full cache cleanup on startup\n"
            printf "  --skip-package-check: Skip package version verification for this run\n"
            printf "  --rebuild-env: Remove and rebuild the conda environment\n"
            printf "  --no-git-update: Skip git update for this run (overrides AUTO_GIT_UPDATE)\n"
            printf "  --help, -h: Show this help\n"
            printf "\n${GREEN}Repository Selection (first-time setup only):${NC}\n"
            printf "  On first run, you'll be prompted to choose between:\n"
            printf "  1) Official Repository (deepbeepmeep/Wan2GP) - Standard version\n"
            printf "  2) Custom Fork - Enhanced fork with additional features\n"
            printf "\n${GREEN}Configuration:${NC}\n"
            printf "  Edit wan2gp-config.sh to customize settings:\n"
            printf "  • DEFAULT_SAGE_VERSION: Set default SageAttention version (2 or 3)\n"
            printf "                         2 = SageAttention 2.2.0 (recommended, Python >=3.9)\n"
            printf "                         3 = SageAttention3 Blackwell (requires Python >=3.13)\n"
            printf "  • DEFAULT_ENABLE_TCMALLOC: Enable TCMalloc for better memory (default: true)\n"
            printf "  • DEFAULT_SERVER_PORT: Default Gradio server port (default: 7862)\n"
            printf "  • TEMP_CACHE_DIR: Custom temp cache directory (empty = system default)\n"
            printf "  • AUTO_CACHE_CLEANUP: Enable/disable automatic cache cleanup (default: false)\n"
            printf "  • AUTO_GIT_UPDATE: Enable/disable automatic git updates (default: false)\n"
            printf "  • AUTO_CHECK_PACKAGES: Check package versions on startup (default: true)\n"
            printf "  • AUTO_FIX_PACKAGE_MISMATCHES: Auto-fix version mismatches (default: true)\n"
            printf "  • AUTO_UPGRADE_SAGE: Auto-upgrade SageAttention on version mismatch (default: false)\n"
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
    elif [[ "$INSTALLED_SAGE_VERSION" =~ ^sageattn3: ]]; then
        # Extract just the version number for display
        DISPLAY_VERSION="${INSTALLED_SAGE_VERSION#sageattn3:}"
        printf "${GREEN}Starting Wan2GP in ${MODE} mode with SageAttention3 (v${DISPLAY_VERSION})!${NC}\n"
        printf "${BLUE}Using microscaling FP4 attention optimized for Blackwell GPUs${NC}\n"
    else
        printf "${YELLOW}Note: SageAttention3 not installed (version ${INSTALLED_SAGE_VERSION} found)${NC}\n"
        printf "${GREEN}Starting Wan2GP in ${MODE} mode with SageAttention ${INSTALLED_SAGE_VERSION}...${NC}\n"
        printf "${BLUE}To install SageAttention3: Upgrade to Python 3.13 and use --rebuild-env${NC}\n"
    fi
else
    if [[ "$INSTALLED_SAGE_VERSION" == "not_installed" ]]; then
        printf "${RED}WARNING: SageAttention is not installed!${NC}\n"
        printf "${YELLOW}Wan2GP will run with standard attention (slower)${NC}\n"
    elif [[ "$INSTALLED_SAGE_VERSION" =~ ^sageattn3: ]]; then
        # SageAttention3 is installed but user requested v2
        DISPLAY_VERSION="${INSTALLED_SAGE_VERSION#sageattn3:}"
        printf "${GREEN}Starting Wan2GP in ${MODE} mode with SageAttention3 (v${DISPLAY_VERSION})...${NC}\n"
        printf "${BLUE}Note: SageAttention3 provides up to 5x speedup with FP4 attention${NC}\n"
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
