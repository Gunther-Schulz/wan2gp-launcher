#!/bin/bash
#########################################################
# Stable Diffusion WebUI Forge Classic - Conda Environment Runner
# This script creates/activates conda environment and lets Forge Classic
# manage package installation intelligently
#
# Path Validation:
#   The script validates all configured paths before starting:
#   - MODELS_DIR: Must exist and be readable (exit if not)
#   - OUTPUT_DIR: Must exist (auto-created if AUTO_OUTPUT_VALIDATION=true)
#   - TEMP_CACHE_DIR: Must exist and be writable (exit if not)
#   This prevents startup with invalid paths.
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

# Load shared library with common functions
if [[ -f "${SCRIPT_DIR}/launcher-common.sh" ]]; then
    source "${SCRIPT_DIR}/launcher-common.sh"
else
    echo "ERROR: launcher-common.sh not found in ${SCRIPT_DIR}"
    echo "This file is required for the launcher to function properly."
    exit 1
fi

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
    
    # Package verification configuration
    [[ -z "$AUTO_CHECK_PACKAGES" ]] && AUTO_CHECK_PACKAGES=true
    [[ -z "$AUTO_FIX_PACKAGE_MISMATCHES" ]] && AUTO_FIX_PACKAGE_MISMATCHES=true
    
    # System paths (empty TEMP_CACHE_DIR means use system default)
    [[ -z "$CONDA_EXE" ]] && CONDA_EXE="/opt/miniconda3/bin/conda"
    
    # Directory configuration
    [[ -z "$MODELS_DIR_DEFAULT" ]] && MODELS_DIR_DEFAULT=""
    [[ -z "$CUSTOM_MODELS_DIR" ]] && CUSTOM_MODELS_DIR=""
    [[ -z "$AUTO_OUTPUT_VALIDATION" ]] && AUTO_OUTPUT_VALIDATION=true
    
    # Performance configuration
    [[ -z "$DEFAULT_ENABLE_TCMALLOC" ]] && DEFAULT_ENABLE_TCMALLOC=true
    [[ -z "$DEFAULT_ENABLE_SAGE" ]] && DEFAULT_ENABLE_SAGE=true
    [[ -z "$DEFAULT_SAGE_VERSION" ]] && DEFAULT_SAGE_VERSION="auto"
    [[ -z "$AUTO_UPGRADE_SAGE" ]] && AUTO_UPGRADE_SAGE=false
    
    # Browser configuration
    [[ -z "$AUTO_LAUNCH_BROWSER" ]] && AUTO_LAUNCH_BROWSER="Disable"
    
    # Environment configuration
    [[ -z "$CONDA_ENV_NAME" ]] && CONDA_ENV_NAME="sd-webui-forge-classic"
    [[ -z "$CONDA_ENV_FILE" ]] && CONDA_ENV_FILE="environment-forge.yml"
    
    # Privacy configuration
    [[ -z "$DISABLE_ERROR_REPORTING" ]] && DISABLE_ERROR_REPORTING=true
    
    # Extensions configuration
    [[ -z "$AUTO_INSTALL_EXTENSIONS" ]] && AUTO_INSTALL_EXTENSIONS=true
    # Default extensions array (empty by default, populated by config file)
    if [[ -z "${EXTENSIONS_TO_INSTALL[@]}" ]]; then
        EXTENSIONS_TO_INSTALL=()
    fi
    
    # Repository configuration
    [[ -z "$AUTO_USE_CUSTOM_REPO" ]] && AUTO_USE_CUSTOM_REPO=false
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

# Early parsing of flags that need to be processed before environment checks
REBUILD_ENV=false
SKIP_PACKAGE_CHECK=false
SAGE_VERSION="$DEFAULT_SAGE_VERSION"  # Start with config value: "auto", "2", or "3"
SAGE_VERSION_EXPLICIT=false  # Track if user explicitly set version via flag
for arg in "$@"; do
    case $arg in
        --rebuild-env)
            REBUILD_ENV=true
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

# WebUI Forge Classic directory (assuming it's in the same parent directory as this script)
WEBUI_DIR="${SCRIPT_DIR}/sd-webui-forge-classic"

# Note: Color definitions now loaded from launcher-common.sh

# Automatically select environment based on SageAttention version configuration
# SageAttention3 (version 3) → Python 3.13 environment (no MediaPipe)
# SageAttention 2.2.0 (version 2 or "auto") → Python 3.11 environment (with MediaPipe)
if [[ "$SAGE_VERSION" == "3" ]]; then
    # Use SageAttention3 environment (Python 3.13)
    CONDA_ENV_NAME="sd-webui-forge-classic-sage3"
    CONDA_ENV_FILE="environment-forge-sage3.yml"
    printf "${YELLOW}═══════════════════════════════════════════════════════════${NC}\n"
    printf "${GREEN}Auto-selected: SageAttention3 environment (Python 3.13)${NC}\n"
    if [[ "$SAGE_VERSION_EXPLICIT" == "true" ]]; then
        printf "${BLUE}   Reason: --sage3 flag specified${NC}\n"
    else
        printf "${BLUE}   Reason: DEFAULT_SAGE_VERSION=\"3\" in forge-config.sh${NC}\n"
    fi
    printf "${RED}⚠ WARNING: MediaPipe is NOT available in Python 3.13${NC}\n"
    printf "${YELLOW}   Extensions like adetailer will NOT work without MediaPipe${NC}\n"
    printf "${YELLOW}   Set DEFAULT_SAGE_VERSION=\"2\" in forge-config.sh to use MediaPipe${NC}\n"
    printf "${YELLOW}═══════════════════════════════════════════════════════════${NC}\n"
else
    # Use default environment (Python 3.11) for SageAttention 2.2.0 or "auto"
    # This environment supports MediaPipe
    CONDA_ENV_NAME="${CONDA_ENV_NAME:-sd-webui-forge-classic}"
    CONDA_ENV_FILE="${CONDA_ENV_FILE:-environment-forge.yml}"
    if [[ "$SAGE_VERSION_EXPLICIT" == "true" ]] && [[ "$SAGE_VERSION" == "2" ]]; then
        printf "${BLUE}Using SageAttention 2.2.0 environment (Python 3.11) - MediaPipe enabled${NC}\n"
    elif [[ "$SAGE_VERSION" == "auto" ]]; then
        printf "${BLUE}Using default environment (Python 3.11) - MediaPipe enabled, SageAttention auto-detect${NC}\n"
    fi
fi

# Pretty print delimiter
delimiter="################################################################"

printf "\n%s\n" "${delimiter}"
printf "${GREEN}Stable Diffusion WebUI Forge Classic - Conda Runner${NC}\n"
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

# Repository selection function
select_repository() {
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Repository Selection${NC}\n"
    printf "%s\n" "${delimiter}"
    printf "${BLUE}Choose which repository to clone:${NC}\n"
    printf "\n"
    printf "${YELLOW}1) Official Repository (Recommended for most users)${NC}\n"
    printf "   ${DEFAULT_REPO}\n"
    printf "   - Latest stable features\n"
    printf "   - Regular updates from maintainer\n"
    printf "   - Community support\n"
    printf "\n"
    printf "${YELLOW}2) Custom Fork (Your modifications)${NC}\n"
    printf "   ${CUSTOM_REPO}\n"
    printf "   - Includes your custom changes\n"
    printf "   - Qwen model fixes included\n"
    printf "   - Your personal modifications\n"
    printf "\n"
    
    while true; do
        printf "${GREEN}Enter your choice [1-2] (default: 1): ${NC}"
        read -r choice
        
        # Default to 1 if empty
        if [[ -z "$choice" ]]; then
            choice=1
        fi
        
        case $choice in
            1)
                SELECTED_REPO="$DEFAULT_REPO"
                REPO_TYPE="official"
                printf "${GREEN}✓ Selected: Official Repository${NC}\n"
                break
                ;;
            2)
                SELECTED_REPO="$CUSTOM_REPO"
                REPO_TYPE="fork"
                printf "${GREEN}✓ Selected: Custom Fork${NC}\n"
                break
                ;;
            *)
                printf "${RED}Invalid choice. Please enter 1 or 2.${NC}\n"
                ;;
        esac
    done
    
    printf "\n${BLUE}Repository: ${SELECTED_REPO}${NC}\n"
    printf "${BLUE}Branch: ${DEFAULT_BRANCH}${NC}\n"
}

# Check if WebUI directory exists, clone if not
if [[ ! -d "${WEBUI_DIR}" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${YELLOW}Stable Diffusion WebUI Forge Classic directory not found.${NC}\n"
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
    
    # Repository selection: auto-select if configured, otherwise prompt
    if [[ "$AUTO_USE_CUSTOM_REPO" == "true" ]] && [[ -n "$CUSTOM_REPO" ]]; then
        # Auto-select custom repo
        SELECTED_REPO="$CUSTOM_REPO"
        REPO_TYPE="fork"
        printf "${GREEN}Auto-selected custom repository: ${CUSTOM_REPO}${NC}\n"
        printf "${BLUE}Branch: ${DEFAULT_BRANCH}${NC}\n"
    else
        # Interactive repository selection
        select_repository
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Cloning repository...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Clone the selected repository
    git clone -b "${DEFAULT_BRANCH}" "${SELECTED_REPO}" "${WEBUI_DIR}"
    if [[ $? -ne 0 ]]; then
        printf "\n%s\n" "${delimiter}"
        printf "${RED}ERROR: Failed to clone repository${NC}\n"
        printf "${YELLOW}Repository: ${SELECTED_REPO}${NC}\n"
        printf "${YELLOW}Branch: ${DEFAULT_BRANCH}${NC}\n"
        printf "${YELLOW}Possible causes and solutions:${NC}\n"
        printf "  1. No internet connection - check your network\n"
        printf "  2. GitHub is down - try again later\n"
        printf "  3. Repository URL is incorrect - check configuration\n"
        printf "  4. Branch '${DEFAULT_BRANCH}' doesn't exist - check branch name\n"
        printf "  5. Insufficient disk space - free up space\n"
        printf "  6. Permission issues - check directory permissions\n"
        printf "%s\n" "${delimiter}"
        exit 1
    fi
    
    # Set up remote configuration based on repository type
    cd "${WEBUI_DIR}"
    if [[ "$REPO_TYPE" == "fork" ]]; then
        printf "${BLUE}Setting up fork remote configuration...${NC}\n"
        # Add upstream remote for fork
        git remote add upstream "${DEFAULT_REPO}"
        printf "${GREEN}✓ Added upstream remote: ${DEFAULT_REPO}${NC}\n"
        printf "${BLUE}You can sync with upstream using: git pull upstream ${DEFAULT_BRANCH}${NC}\n"
    else
        printf "${BLUE}Using official repository - no additional remotes needed${NC}\n"
    fi
    cd - > /dev/null
    
    printf "${GREEN}Successfully cloned Stable Diffusion WebUI Forge Classic repository${NC}\n"
    printf "${GREEN}Repository type: ${REPO_TYPE}${NC}\n"
fi

# Package version verification function
verify_package_versions() {
    if [[ "$SKIP_PACKAGE_CHECK" == "true" ]]; then
        printf "${BLUE}Package version check skipped (--skip-package-check flag)${NC}\n"
        return 0
    fi
    
    if [[ "$AUTO_CHECK_PACKAGES" != "true" ]]; then
        printf "${BLUE}Package version check disabled (AUTO_CHECK_PACKAGES=false)${NC}\n"
        return 0
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Verifying package versions...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    local requirements_file="${WEBUI_DIR}/requirements.txt"
    
    if [[ ! -f "$requirements_file" ]]; then
        printf "${YELLOW}Warning: requirements.txt not found, skipping version check${NC}\n"
        return 0
    fi
    
    # Activate conda environment for python access
    eval "$("${CONDA_EXE}" shell.bash hook)" 2>/dev/null
    conda activate "${ENV_NAME}" 2>/dev/null
    
    # Use Python to check for version mismatches
    local check_result=$(python -c "
import sys
import re
from importlib.metadata import version, PackageNotFoundError

def parse_requirement(line):
    line = line.strip()
    if not line or line.startswith('#'):
        return None, None
    # Remove comments
    line = line.split('#')[0].strip()
    # Parse package==version or package>=version
    match = re.match(r'^([a-zA-Z0-9_-]+)(==|>=)([0-9.]+)', line)
    if match:
        return match.group(1), (match.group(2), match.group(3))  # Keep original case
    return None, None

def normalize_version(ver_str):
    '''Strip build/local version identifiers like +cu118 or +cpu'''
    # Split on + to remove build identifiers like +cu118
    base_ver = ver_str.split('+')[0]
    # Extract just the numeric version parts (handles any number of parts)
    # e.g., 2.0.1.dev20231201 -> 2.0.1, 4.12.0.88 -> 4.12.0.88
    import re
    match = re.match(r'^(\d+(?:\.\d+)*)', base_ver)
    if match:
        return match.group(1)
    return base_ver

def get_package_version(pkg_name):
    '''Try multiple name variations to find package'''
    # Try original name first
    try:
        return version(pkg_name)
    except PackageNotFoundError:
        pass
    
    # Try with underscores instead of hyphens
    try:
        return version(pkg_name.replace('-', '_'))
    except PackageNotFoundError:
        pass
    
    # Try with hyphens instead of underscores
    try:
        return version(pkg_name.replace('_', '-'))
    except PackageNotFoundError:
        pass
    
    # Try lowercase
    try:
        return version(pkg_name.lower())
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
        
        # Compare version numbers as tuples (handles trailing zeros properly)
        try:
            inst_parts = [int(x) for x in installed_ver.split('.')]
            req_parts = [int(x) for x in required_ver.split('.')]
            # Pad to same length with zeros
            max_len = max(len(inst_parts), len(req_parts))
            inst_parts += [0] * (max_len - len(inst_parts))
            req_parts += [0] * (max_len - len(req_parts))
            
            if operator == '==':
                # Exact match: 1.22.0 should equal 1.22 after padding
                if inst_parts != req_parts:
                    mismatches.append(f'{pkg_name}|{installed_ver}|{required_ver}|exact')
            elif operator == '>=':
                # Minimum version check
                if inst_parts < req_parts:
                    mismatches.append(f'{pkg_name}|{installed_ver}|{required_ver}|minimum')
        except (ValueError, AttributeError):
            # Skip packages with non-standard version formats
            pass
    except PackageNotFoundError:
        # Skip packages that truly can't be found - pip will handle these
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
        
        # Parse and display mismatches
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
                missing)
                    printf "${RED}  • ${pkg}: NOT INSTALLED, required=${required}${NC}\n"
                    has_critical=true
                    ;;
            esac
        done <<< "$check_result"
        
        printf "${BLUE}Total mismatches found: ${mismatch_count}${NC}\n"
        
        if [[ "$has_critical" == "true" ]]; then
            if [[ "$AUTO_FIX_PACKAGE_MISMATCHES" == "true" ]]; then
                printf "\n${GREEN}Auto-fixing package mismatches...${NC}\n"
                
                printf "${BLUE}Running: pip install -r requirements.txt${NC}\n"
                pip install -r "$requirements_file"
                
                if [[ $? -eq 0 ]]; then
                    printf "${GREEN}✓ Successfully updated packages to match requirements${NC}\n"
                    return 0
                else
                    printf "${RED}✗ Failed to update some packages${NC}\n"
                    printf "${YELLOW}You may need to manually run: pip install -r requirements.txt${NC}\n"
                    return 1
                fi
            else
                printf "\n${YELLOW}AUTO_FIX_PACKAGE_MISMATCHES is disabled${NC}\n"
                printf "${YELLOW}To fix, run: pip install -r requirements.txt${NC}\n"
                printf "${YELLOW}Or enable auto-fix in forge-config.sh${NC}\n"
                printf "${BLUE}Continuing anyway (Forge Classic will handle package installation)...${NC}\n"
                return 0
            fi
        fi
    fi
    
    return 0
}

# Extension management function
install_extensions() {
    if [[ "$AUTO_INSTALL_EXTENSIONS" != "true" ]]; then
        printf "${BLUE}Automatic extension installation disabled (AUTO_INSTALL_EXTENSIONS=false)${NC}\n"
        return 0
    fi
    
    if [[ ${#EXTENSIONS_TO_INSTALL[@]} -eq 0 ]]; then
        printf "${BLUE}No extensions configured for installation${NC}\n"
        return 0
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Managing extensions...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Ensure extensions directory exists
    local extensions_dir="${WEBUI_DIR}/extensions"
    mkdir -p "${extensions_dir}"
    
    for extension_url in "${EXTENSIONS_TO_INSTALL[@]}"; do
        # Skip empty or commented lines
        if [[ -z "$extension_url" ]] || [[ "$extension_url" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Extract extension name from URL (last part of path without .git)
        local extension_name=$(basename "$extension_url" .git)
        local extension_path="${extensions_dir}/${extension_name}"
        
        printf "${BLUE}Processing extension: ${extension_name}${NC}\n"
        
        if [[ ! -d "$extension_path" ]]; then
            printf "${YELLOW}Extension not found, cloning: ${extension_url}${NC}\n"
            
            # Clone the extension
            git clone "$extension_url" "$extension_path"
            if [[ $? -eq 0 ]]; then
                printf "${GREEN}✓ Successfully cloned extension: ${extension_name}${NC}\n"
                
                # Run extension installer if it exists
                if [[ -f "${extension_path}/install.py" ]]; then
                    printf "${BLUE}Running extension installer for ${extension_name}...${NC}\n"
                    cd "$extension_path"
                    python install.py 2>/dev/null || printf "${YELLOW}Warning: Extension installer failed or not needed${NC}\n"
                    cd "${WEBUI_DIR}"
                fi
            else
                printf "${RED}ERROR: Failed to clone extension: ${extension_name}${NC}\n"
                printf "${YELLOW}Possible causes:${NC}\n"
                printf "  1. Network connection issues\n"
                printf "  2. Invalid repository URL: ${extension_url}\n"
                printf "  3. Repository access restrictions\n"
                printf "  4. Insufficient disk space\n"
                continue
            fi
        else
            printf "${GREEN}✓ Extension already exists: ${extension_name}${NC}\n"
            
            # Update extension if git updates are enabled
            if [[ "$AUTO_GIT_UPDATE" == "true" ]] && [[ "$DISABLE_GIT_UPDATE" != "true" ]]; then
                printf "${BLUE}Checking for updates to ${extension_name}...${NC}\n"
                cd "$extension_path"
                
                # Store current commit hash
                local current_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
                
                # Pull latest changes
                git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || {
                    printf "${YELLOW}Warning: Could not update extension ${extension_name} (this is normal if offline)${NC}\n"
                }
                
                # Check if commit changed
                local new_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
                
                if [[ "$current_commit" != "$new_commit" ]] && [[ "$new_commit" != "unknown" ]]; then
                    printf "${GREEN}✓ Extension ${extension_name} updated${NC}\n"
                    
                    # Run extension installer if it exists and extension was updated
                    if [[ -f "install.py" ]]; then
                        printf "${BLUE}Running extension installer for updated ${extension_name}...${NC}\n"
                        python install.py 2>/dev/null || printf "${YELLOW}Warning: Extension installer failed or not needed${NC}\n"
                    fi
                else
                    printf "${GREEN}✓ Extension ${extension_name} is up to date${NC}\n"
                fi
                
                cd "${WEBUI_DIR}"
            else
                printf "${BLUE}Extension updates disabled - skipping update check${NC}\n"
            fi
        fi
    done
    
    printf "${GREEN}Extension management completed${NC}\n"
}

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
DISABLE_SAGE=false  # Initialize from config (will be set to true if DEFAULT_ENABLE_SAGE=false)
if [[ "$DEFAULT_ENABLE_SAGE" != "true" ]]; then
    DISABLE_SAGE=true
fi
FORCE_CACHE_CLEANUP=false  # Force full cache cleanup
DISABLE_GIT_UPDATE=false   # Flag to disable git updates for this run
# Note: REBUILD_ENV and SKIP_PACKAGE_CHECK already parsed in early parsing section
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
            # Already handled in early parsing, just skip
            shift
            ;;
        --skip-package-check)
            # Already handled in early parsing, just skip
            shift
            ;;
        --no-git-update)
            DISABLE_GIT_UPDATE=true
            shift
            ;;
        --disable-sage)
            DISABLE_SAGE=true
            shift
            ;;
        --sage3)
            # Already handled in early parsing, just skip
            shift
            ;;
        --sage2)
            # Already handled in early parsing, just skip
            shift
            ;;
        --help|-h)
            printf "${GREEN}Stable Diffusion WebUI Forge Classic Usage:${NC}\n"
            printf "  Default (no args): Use configured default models directory with SageAttention 2\n"
            printf "  --models-dir PATH: Override the models directory location\n"
            printf "  --use-custom-dir, -c: Use preset custom models dir (from config)\n"
            printf "  --output-dir PATH: Override the output directory for generated images\n"
            printf "  --disable-tcmalloc: Disable TCMalloc (if you experience library conflicts)\n"
            printf "\n${GREEN}SageAttention Options:${NC}\n"
            printf "  --sage2: Use SageAttention 2.2.0 (default, recommended for most GPUs)\n"
            printf "           Compatible with: RTX 3060/3090, RTX 4060/4090, A100, H100\n"
            printf "           Requirements: Python >=3.9, PyTorch >=2.0, CUDA >=12.0\n"
            printf "  --sage3: Use SageAttention3 (microscaling FP4 for Blackwell GPUs)\n"
            printf "           Optimized for: RTX 5070/5080/5090 (Blackwell architecture)\n"
            printf "           Requirements: Python >=3.13, PyTorch >=2.8.0, CUDA >=12.8\n"
            printf "           ⚠ Automatically switches to Python 3.13 environment (MediaPipe NOT available)\n"
            printf "  --sage2: Use SageAttention 2.2.0 (forces Python 3.11 environment with MediaPipe)\n"
            printf "  --disable-sage: Disable SageAttention (use PyTorch attention instead)\n"
            printf "\n${GREEN}Other Options:${NC}\n"
            printf "  --clean-cache: Force full cache cleanup on startup\n"
            printf "  --rebuild-env: Remove and rebuild the conda environment\n"
            printf "  --skip-package-check: Skip package version verification for this run\n"
            printf "  --no-git-update: Skip git update for this run\n"
            printf "  --help, -h: Show this help\n"
            printf "\n${GREEN}Configuration:${NC}\n"
            printf "  Edit forge-config.sh to customize settings:\n"
            printf "  • CUSTOM_REPO: Your fork repository URL\n"
            printf "  • DEFAULT_REPO: Official repository URL\n"
            printf "  • DEFAULT_BRANCH: Default branch to use\n"
            printf "  • TEMP_CACHE_DIR: Custom temp cache directory\n"
            printf "  • AUTO_CACHE_CLEANUP: Enable/disable automatic cache cleanup\n"
            printf "  • CACHE_SIZE_THRESHOLD: Cache cleanup threshold in MB (default: 100)\n"
            printf "  • AUTO_GIT_UPDATE: Enable/disable automatic git updates\n"
            printf "  • AUTO_CHECK_PACKAGES: Check package versions on startup (default: true)\n"
            printf "  • AUTO_FIX_PACKAGE_MISMATCHES: Auto-fix version mismatches (default: true)\n"
            printf "  • MODELS_DIR_DEFAULT: Default models directory\n"
            printf "  • OUTPUT_DIR: Default output directory\n"
            printf "  • CONDA_EXE: Path to conda executable\n"
            printf "  • AUTO_INSTALL_EXTENSIONS: Enable/disable automatic extension installation\n"
            printf "  • EXTENSIONS_TO_INSTALL: Array of extension URLs to auto-install\n"
            printf "  • AUTO_LAUNCH_BROWSER: Browser auto-launch (Disable/Local/Remote)\n"
            printf "  • DEFAULT_SAGE_VERSION: Default SageAttention version (2, 3, \"auto\", or \"none\")\n"
            printf "                          \"2\" = Python 3.11 environment (MediaPipe enabled)\n"
            printf "                          \"3\" = Python 3.13 environment (SageAttention3, NO MediaPipe)\n"
            printf "                          \"auto\" = Auto-detect based on GPU (defaults to 2)\n"
            printf "                          \"none\" = Disable SageAttention\n"
            printf "  • AUTO_UPGRADE_SAGE: Auto-upgrade SageAttention when old version detected (default: false)\n"
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

# Install/update extensions (after argument parsing so DISABLE_GIT_UPDATE is set)
install_extensions

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
        # Capture conda output and filter long error messages
        CONDA_OUTPUT=$(mktemp)
        CONDA_ERROR=$(mktemp)
        
        printf "${BLUE}Creating conda environment (this may take a few minutes)...${NC}\n"
        "${CONDA_EXE}" env create -f "${SCRIPT_DIR}/${CONDA_ENV_FILE}" > "$CONDA_OUTPUT" 2> "$CONDA_ERROR"
        CONDA_EXIT_CODE=$?
        
        if [[ $CONDA_EXIT_CODE -ne 0 ]]; then
            printf "\n%s\n" "${delimiter}"
            printf "${RED}ERROR: Failed to create conda environment${NC}\n"
            printf "%s\n" "${delimiter}"
            
            # Show a summary of the error instead of the full conflict tree
            ERROR_LINES=$(wc -l < "$CONDA_ERROR" | tr -d ' ')
            
            if [[ $ERROR_LINES -gt 50 ]]; then
                printf "${YELLOW}Conda dependency conflict detected (error output truncated)${NC}\n"
                printf "${BLUE}Showing first 20 and last 10 lines of error:${NC}\n"
                printf "\n${YELLOW}--- First 20 lines ---${NC}\n"
                head -n 20 "$CONDA_ERROR"
                printf "\n${YELLOW}... (${ERROR_LINES} total lines, showing last 10) ...${NC}\n"
                printf "\n${YELLOW}--- Last 10 lines ---${NC}\n"
                tail -n 10 "$CONDA_ERROR"
                
                # Try to extract key conflict information
                printf "\n${BLUE}Key conflicts detected:${NC}\n"
                grep -E "(conflicts with|would require|but there are no viable)" "$CONDA_ERROR" | head -n 5 | sed 's/^/  /'
            else
                # Show full error if it's short
                cat "$CONDA_ERROR"
            fi
            
            printf "\n%s\n" "${delimiter}"
            printf "${YELLOW}Possible causes and solutions:${NC}\n"
            printf "  1. Dependency conflicts - check ${CONDA_ENV_FILE} for incompatible packages\n"
            printf "  2. Network issues - check internet connection\n"
            printf "  3. Disk space - ensure sufficient free space\n"
            printf "  4. Conda channels - try: conda config --add channels conda-forge\n"
            printf "  5. Permission issues - check write permissions\n"
            printf "  6. Python version - try a different Python version in ${CONDA_ENV_FILE}\n"
            printf "\n${BLUE}Full error log saved to: ${CONDA_ERROR}${NC}\n"
            printf "%s\n" "${delimiter}"
            
            rm -f "$CONDA_OUTPUT" "$CONDA_ERROR"
            exit 1
        else
            # Show success message
            if [[ -s "$CONDA_OUTPUT" ]]; then
                printf "${GREEN}✓ Environment creation output:${NC}\n"
                tail -n 5 "$CONDA_OUTPUT" | sed 's/^/  /'
            fi
            rm -f "$CONDA_OUTPUT" "$CONDA_ERROR"
        fi
        
        printf "\n%s\n" "${delimiter}"
        printf "${GREEN}Conda environment created successfully!${NC}\n"
        printf "${BLUE}Installing additional packages...${NC}\n"
        printf "%s\n" "${delimiter}"
        
        # Activate environment for additional packages
        eval "$("${CONDA_EXE}" shell.bash hook)"
        conda activate "${ENV_NAME}"
        
        # Check Python version and handle compatibility
        PYTHON_MAJOR_MINOR=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
        
        if [[ "$PYTHON_MAJOR_MINOR" == "3.13" ]]; then
            printf "${BLUE}Python 3.13 detected${NC}\n"
            # Note: mediapipe is NOT available for Python 3.13
            printf "${YELLOW}⚠ Note: mediapipe is not available for Python 3.13 (extensions like adetailer will not work)${NC}\n"
        elif [[ "$PYTHON_MAJOR_MINOR" == "3.12" ]]; then
            printf "${BLUE}Python 3.12 detected - compatible with mediapipe and SageAttention 2.2.0${NC}\n"
            # Force SageAttention 2.2.0 for Python 3.12 (mediapipe compatibility)
            if [[ "$SAGE_VERSION" == "3" ]] || [[ "$SAGE_VERSION" == "auto" ]]; then
                printf "${YELLOW}⚠ SageAttention3 requires Python 3.13, but mediapipe requires Python <=3.12${NC}\n"
                printf "${YELLOW}⚠ Using SageAttention 2.2.0 instead (still provides 2-5x speedup)${NC}\n"
                SAGE_VERSION="2"
            fi
        elif [[ "$PYTHON_MAJOR_MINOR" == "3.11" ]]; then
            printf "${BLUE}Python 3.11 detected - compatible with mediapipe and SageAttention 2.2.0${NC}\n"
            # Force SageAttention 2.2.0 for Python 3.11 (mediapipe compatibility)
            if [[ "$SAGE_VERSION" == "3" ]] || [[ "$SAGE_VERSION" == "auto" ]]; then
                printf "${YELLOW}⚠ SageAttention3 requires Python 3.13, but mediapipe requires Python <=3.12${NC}\n"
                printf "${YELLOW}⚠ Using SageAttention 2.2.0 instead (still provides 2-5x speedup)${NC}\n"
                SAGE_VERSION="2"
            fi
        fi
        
        # Install requirements.txt FIRST (includes PyTorch and all dependencies)
        requirements_file="${WEBUI_DIR}/requirements.txt"
        if [[ -f "$requirements_file" ]]; then
            printf "\n${BLUE}Installing packages from requirements.txt (this includes PyTorch)...${NC}\n"
            printf "${YELLOW}This may take several minutes...${NC}\n"
            pip install -r "$requirements_file"
            if [[ $? -eq 0 ]]; then
                printf "${GREEN}✓ Successfully installed all packages from requirements.txt${NC}\n"
                # Verify PyTorch is now installed
                if python -c "import torch" 2>/dev/null; then
                    PYTORCH_VERSION=$(python -c "import torch; print(torch.__version__)" 2>/dev/null)
                    printf "${GREEN}✓ PyTorch ${PYTORCH_VERSION} is now installed${NC}\n"
                else
                    printf "${RED}✗ WARNING: PyTorch installation may have failed${NC}\n"
                fi
            else
                printf "${RED}✗ Failed to install some packages from requirements.txt${NC}\n"
                printf "${YELLOW}Continuing anyway - Forge Classic may install missing packages on launch${NC}\n"
            fi
            
        else
            printf "${YELLOW}Warning: requirements.txt not found at ${requirements_file}${NC}\n"
            printf "${YELLOW}PyTorch and other dependencies will be installed by Forge Classic on first launch${NC}\n"
        fi
        
        
        # Install SageAttention from source for better performance
        if [[ "$SAGE_VERSION" == "3" ]]; then
            # Check Python version for SageAttention3
            PYTHON_VERSION=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
            if [[ $(python -c "import sys; print(1 if sys.version_info >= (3, 13) else 0)" 2>/dev/null) == "0" ]]; then
                printf "${RED}ERROR: SageAttention3 requires Python 3.13 or higher${NC}\n"
                printf "${YELLOW}Current Python version: ${PYTHON_VERSION}${NC}\n"
                printf "${YELLOW}Falling back to SageAttention 2.2.0 installation...${NC}\n"
                SAGE_VERSION="2"
            else
                printf "${BLUE}Installing SageAttention3 from source (Blackwell FP4 attention)...${NC}\n"
                printf "${YELLOW}Requirements: Python >=3.13, PyTorch >=2.8.0, CUDA >=12.8${NC}\n"
            fi
        fi
        
        if [[ "$SAGE_VERSION" != "3" ]]; then
            printf "${BLUE}Installing SageAttention 2.2.0 from source...${NC}\n"
            printf "${YELLOW}Requirements: Python >=3.9, PyTorch >=2.0, CUDA >=12.0${NC}\n"
        fi
        
        # Check if PyTorch is installed (required for SageAttention compilation)
        if ! python -c "import torch" 2>/dev/null; then
            printf "${YELLOW}PyTorch not yet installed. SageAttention compilation will be deferred.${NC}\n"
            printf "${BLUE}Forge Classic will install PyTorch first, then SageAttention can be compiled.${NC}\n"
            printf "${BLUE}Skipping SageAttention installation during environment setup.${NC}\n"
        # Check CUDA availability
        elif ! command -v nvcc &> /dev/null; then
            printf "${YELLOW}Warning: NVCC not found. SageAttention requires CUDA for compilation.${NC}\n"
            printf "${YELLOW}Skipping SageAttention installation. Forge Classic will work without it.${NC}\n"
        else
            # Set CUDA_HOME to conda environment to avoid version mismatch
            export CUDA_HOME="${CONDA_PREFIX}"
            printf "${BLUE}Setting CUDA_HOME to conda environment: ${CUDA_HOME}${NC}\n"
            
            # Verify CUDA version compatibility
            CONDA_CUDA_VERSION=$(nvcc --version | grep "release" | sed 's/.*release \([0-9]\+\.[0-9]\+\).*/\1/')
            printf "${BLUE}Using CUDA version: ${CONDA_CUDA_VERSION}${NC}\n"
            
            # Auto-detect GPU architectures for compilation
            # This ensures SageAttention is compiled for all GPUs in the system
            DETECTED_ARCHS=()
            if command -v nvidia-smi &> /dev/null; then
                printf "${BLUE}Auto-detecting GPU compute capabilities...${NC}\n"
                # Get all unique compute capabilities from all GPUs
                while IFS= read -r compute_cap; do
                    compute_cap=$(echo "$compute_cap" | tr -d ' ')
                    if [[ -n "$compute_cap" ]]; then
                        # Map compute capability to CUDA architecture
                        case "$compute_cap" in
                            7.0)
                                DETECTED_ARCHS+=("7.0")
                                ;;
                            7.5)
                                DETECTED_ARCHS+=("7.5")
                                ;;
                            8.0|8.6)
                                DETECTED_ARCHS+=("8.0")
                                ;;
                            8.9)
                                DETECTED_ARCHS+=("8.9")
                                ;;
                            9.0)
                                DETECTED_ARCHS+=("9.0")
                                ;;
                            10.*)
                                DETECTED_ARCHS+=("10.0")
                                ;;
                        esac
                    fi
                done < <(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | sort -u)
                
                if [[ ${#DETECTED_ARCHS[@]} -gt 0 ]]; then
                    # Remove duplicates and sort
                    UNIQUE_ARCHS=($(printf '%s\n' "${DETECTED_ARCHS[@]}" | sort -u))
                    AUTO_TORCH_CUDA_ARCH_LIST=$(IFS=';'; echo "${UNIQUE_ARCHS[*]}")
                    printf "${GREEN}Detected GPU architectures: ${AUTO_TORCH_CUDA_ARCH_LIST}${NC}\n"
                else
                    # Fallback to common architectures if detection fails
                    AUTO_TORCH_CUDA_ARCH_LIST="8.0;8.9"
                    printf "${YELLOW}Could not detect GPU architectures, defaulting to: ${AUTO_TORCH_CUDA_ARCH_LIST}${NC}\n"
                fi
            else
                # Fallback if nvidia-smi not available
                AUTO_TORCH_CUDA_ARCH_LIST="8.0;8.9"
                printf "${YELLOW}nvidia-smi not available, defaulting to: ${AUTO_TORCH_CUDA_ARCH_LIST}${NC}\n"
            fi
            
            # First, ensure we have build dependencies
            printf "${BLUE}Installing build dependencies...${NC}\n"
            pip install ninja packaging wheel setuptools
            
            # Clone and install SageAttention
            SAGE_DIR="/tmp/SageAttention_forge"
            if [[ -d "$SAGE_DIR" ]]; then
                rm -rf "$SAGE_DIR"
            fi
            
            printf "${BLUE}Cloning SageAttention repository...${NC}\n"
            git clone https://github.com/thu-ml/SageAttention.git "$SAGE_DIR"
            if [[ $? -eq 0 ]]; then
                # Detect CPU cores and set parallel compilation
                NPROC=$(nproc)
                # Use 75% of cores (leave some for system), minimum 4, maximum 16
                PARALLEL_JOBS=$(( NPROC * 3 / 4 ))
                PARALLEL_JOBS=$(( PARALLEL_JOBS < 4 ? 4 : PARALLEL_JOBS ))
                PARALLEL_JOBS=$(( PARALLEL_JOBS > 16 ? 16 : PARALLEL_JOBS ))
                
                printf "${BLUE}Detected ${NPROC} CPU cores, using ${PARALLEL_JOBS} parallel jobs${NC}\n"
                
                # Set parallel compilation environment variables
                export MAX_JOBS="${PARALLEL_JOBS}"
                export CMAKE_BUILD_PARALLEL_LEVEL="${PARALLEL_JOBS}"
                export NVCC_APPEND_FLAGS="--threads ${PARALLEL_JOBS}"
                export CUDA_HOME="${CUDA_HOME}"
                export VERBOSE="1"
                
                # Handle version-specific installation
                if [[ "$SAGE_VERSION" == "3" ]]; then
                    # SageAttention3 - navigate to blackwell subdirectory
                    cd "$SAGE_DIR/sageattention3_blackwell"
                    export TORCH_CUDA_ARCH_LIST="8.0;9.0"  # Both Ampere/Ada and Blackwell
                    printf "${GREEN}Installing from sageattention3_blackwell subdirectory${NC}\n"
                    printf "${BLUE}Compiling SageAttention3 (this may take several minutes)...${NC}\n"
                    printf "${BLUE}Features: Microscaling FP4 attention for Blackwell GPUs${NC}\n"
                    
                    # First, uninstall any existing versions
                    printf "${BLUE}Removing old SageAttention versions...${NC}\n"
                    pip uninstall -y sageattention sageattn3 2>/dev/null || true
                    
                    # Compile directly with setup.py
                    # Use set -o pipefail to capture actual exit code through tee
                    set -o pipefail
                    python setup.py install 2>&1 | tee /tmp/sageattention3_forge_initial.log
                    local build_exit_code=$?
                    set +o pipefail
                    
                    if [[ $build_exit_code -eq 0 ]]; then
                        printf "${GREEN}SageAttention3 installed successfully!${NC}\n"
                        printf "${GREEN}Features: FP4 Tensor Cores with up to 5x speedup on RTX 5090${NC}\n"
                        cd "${WEBUI_DIR}"
                        rm -rf "$SAGE_DIR"
                    else
                        printf "${RED}ERROR: Failed to compile SageAttention3${NC}\n"
                        printf "${RED}Exit code: ${build_exit_code}${NC}\n"
                        
                        # Check build log for common errors
                        if grep -q "ModuleNotFoundError.*torch" /tmp/sageattention3_forge_initial.log 2>/dev/null; then
                            printf "${YELLOW}Root cause: PyTorch is not installed${NC}\n"
                            printf "${YELLOW}Solution: Forge Classic will install PyTorch first, then SageAttention3 can be compiled later${NC}\n"
                        elif grep -q "Python version" /tmp/sageattention3_forge_initial.log 2>/dev/null; then
                            printf "${YELLOW}This may be due to:${NC}\n"
                            printf "${YELLOW}  - Python version <3.13${NC}\n"
                        elif grep -q "CUDA" /tmp/sageattention3_forge_initial.log 2>/dev/null; then
                            printf "${YELLOW}This may be due to:${NC}\n"
                            printf "${YELLOW}  - CUDA version <12.8${NC}\n"
                            printf "${YELLOW}  - Missing CUDA development tools${NC}\n"
                        else
                            printf "${YELLOW}This may be due to:${NC}\n"
                            printf "${YELLOW}  - PyTorch version <2.8.0${NC}\n"
                            printf "${YELLOW}  - Missing development tools or insufficient memory${NC}\n"
                        fi
                        printf "${YELLOW}Build log saved to: /tmp/sageattention3_forge_initial.log${NC}\n"
                        printf "${YELLOW}Forge Classic will work without SageAttention3, but may be slower.${NC}\n"
                        cd "${WEBUI_DIR}"
                        # Keep SAGE_DIR for debugging
                    fi
                else
                    # SageAttention 2.2.0 - use root directory
                    cd "$SAGE_DIR"
                    # Use auto-detected architectures or fallback to 8.0;8.9
                    export TORCH_CUDA_ARCH_LIST="${AUTO_TORCH_CUDA_ARCH_LIST:-8.0;8.9}"
                    printf "${BLUE}Compiling SageAttention 2.2.0 for architectures: ${TORCH_CUDA_ARCH_LIST}${NC}\n"
                    printf "${BLUE}This may take several minutes...${NC}\n"
                    
                    # First, uninstall any existing versions
                    printf "${BLUE}Removing old SageAttention versions...${NC}\n"
                    pip uninstall -y sageattention 2>/dev/null || true
                    
                    # Compile directly with setup.py
                    # Use set -o pipefail to capture actual exit code through tee
                    set -o pipefail
                    python setup.py install 2>&1 | tee /tmp/sageattention_initial_build.log
                    build_exit_code=$?
                    set +o pipefail
                    
                    if [[ $build_exit_code -eq 0 ]]; then
                        printf "${GREEN}SageAttention 2.2.0 installed successfully${NC}\n"
                        printf "${GREEN}Features: 2-5x speedup, per-thread quantization, outlier smoothing${NC}\n"
                        cd "${WEBUI_DIR}"
                        rm -rf "$SAGE_DIR"
                    else
                        printf "${RED}ERROR: Failed to compile SageAttention 2.2.0${NC}\n"
                        printf "${RED}Exit code: ${build_exit_code}${NC}\n"
                        
                        # Check build log for common errors
                        if grep -q "ModuleNotFoundError.*torch" /tmp/sageattention_initial_build.log 2>/dev/null; then
                            printf "${YELLOW}Root cause: PyTorch is not installed${NC}\n"
                            printf "${YELLOW}Solution: Forge Classic will install PyTorch first, then SageAttention can be compiled later${NC}\n"
                        elif grep -q "CUDA" /tmp/sageattention_initial_build.log 2>/dev/null; then
                            printf "${YELLOW}This may be due to:${NC}\n"
                            printf "${YELLOW}  - CUDA version mismatch between system and PyTorch${NC}\n"
                            printf "${YELLOW}  - Missing CUDA development tools${NC}\n"
                        else
                            printf "${YELLOW}This may be due to:${NC}\n"
                            printf "${YELLOW}  - Missing development tools${NC}\n"
                            printf "${YELLOW}  - Insufficient memory during compilation${NC}\n"
                            printf "${YELLOW}  - Linker issues with conda environment libraries${NC}\n"
                        fi
                        printf "${YELLOW}Build log saved to: /tmp/sageattention_initial_build.log${NC}\n"
                        printf "${YELLOW}Forge Classic will work without SageAttention, but may be slower.${NC}\n"
                        cd "${WEBUI_DIR}"
                        # Keep SAGE_DIR for debugging
                    fi
                fi
            else
                printf "${RED}ERROR: Failed to clone SageAttention repository${NC}\n"
                printf "${YELLOW}Check your internet connection. Forge Classic will work without SageAttention.${NC}\n"
            fi
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

# Update git repository if enabled
if [[ "$AUTO_GIT_UPDATE" == "true" ]] && [[ "$DISABLE_GIT_UPDATE" != "true" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Checking for updates...${NC}\n"
    printf "%s\n" "${delimiter}"

    # Check if we need to switch remotes based on config
    CURRENT_ORIGIN=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$AUTO_USE_CUSTOM_REPO" == "true" ]] && [[ -n "$CUSTOM_REPO" ]]; then
        # Config says use custom fork
        EXPECTED_REPO="$CUSTOM_REPO"
    else
        # Config says use official repo
        EXPECTED_REPO="$DEFAULT_REPO"
    fi
    
    # Switch origin remote if it doesn't match config
    if [[ -n "$CURRENT_ORIGIN" ]] && [[ "$CURRENT_ORIGIN" != "$EXPECTED_REPO" ]]; then
        printf "${BLUE}Config changed: switching origin remote to match config...${NC}\n"
        printf "${YELLOW}Old origin: ${CURRENT_ORIGIN}${NC}\n"
        printf "${GREEN}New origin: ${EXPECTED_REPO}${NC}\n"
        git remote set-url origin "${EXPECTED_REPO}" 2>/dev/null || {
            printf "${YELLOW}Warning: Could not update origin remote${NC}\n"
        }
        # Fetch from new origin
        printf "${BLUE}Fetching from new origin...${NC}\n"
        git fetch origin "${DEFAULT_BRANCH}" 2>/dev/null || true
    fi

    # Store current commit hash
    CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

    # Always switch to the branch specified in config (DEFAULT_BRANCH)
    printf "${BLUE}Switching to ${DEFAULT_BRANCH} branch (from config)...${NC}\n"
    git checkout "${DEFAULT_BRANCH}" 2>/dev/null || {
        # Branch doesn't exist locally, try to create it from upstream or origin
        if git remote get-url upstream >/dev/null 2>&1; then
            printf "${BLUE}Creating ${DEFAULT_BRANCH} branch from upstream...${NC}\n"
            git checkout -b "${DEFAULT_BRANCH}" "upstream/${DEFAULT_BRANCH}" 2>/dev/null || {
                printf "${YELLOW}Could not create from upstream, trying origin...${NC}\n"
                git checkout -b "${DEFAULT_BRANCH}" "origin/${DEFAULT_BRANCH}" 2>/dev/null || {
                    printf "${RED}ERROR: Could not switch to or create ${DEFAULT_BRANCH} branch${NC}\n"
                }
            }
        else
            printf "${BLUE}Creating ${DEFAULT_BRANCH} branch from origin...${NC}\n"
            git checkout -b "${DEFAULT_BRANCH}" "origin/${DEFAULT_BRANCH}" 2>/dev/null || {
                printf "${RED}ERROR: Could not switch to or create ${DEFAULT_BRANCH} branch${NC}\n"
            }
        fi
    }

    # Pull latest changes from origin (the configured repo - fork or official)
    printf "${BLUE}Pulling latest changes from git repository...${NC}\n"
    printf "${BLUE}Current branch: ${DEFAULT_BRANCH}${NC}\n"
    printf "${BLUE}Pulling from origin ${DEFAULT_BRANCH}...${NC}\n"
    git pull origin "${DEFAULT_BRANCH}" 2>&1 || {
        printf "${YELLOW}Warning: Could not pull from origin ${DEFAULT_BRANCH}${NC}\n"
    }

    # Check if commit changed
    NEW_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

    if [[ "$CURRENT_COMMIT" != "$NEW_COMMIT" ]] && [[ "$NEW_COMMIT" != "unknown" ]]; then
        printf "${GREEN}Repository updated successfully!${NC}\n"
        printf "${BLUE}Forge Classic will handle any package updates on launch${NC}\n"
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

# Comprehensive path validation function
validate_all_paths() {
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Validating configured paths...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    local validation_failed=false
    
    # 1. Validate MODELS_DIR if specified
    if [[ -n "$MODELS_DIR" ]]; then
        printf "${BLUE}Checking models directory: ${MODELS_DIR}${NC}\n"
        
        if [[ ! -d "$MODELS_DIR" ]]; then
            printf "${RED}ERROR: Models directory does not exist: ${MODELS_DIR}${NC}\n"
            printf "${YELLOW}Solutions:${NC}\n"
            printf "  1. Create the directory: mkdir -p \"${MODELS_DIR}\"${NC}\n"
            printf "  2. Fix the path in forge-config.sh${NC}\n"
            printf "  3. Remove MODELS_DIR setting to use WebUI default${NC}\n"
            printf "  4. If using external/network drive, ensure it's mounted${NC}\n"
            validation_failed=true
        elif [[ ! -r "$MODELS_DIR" ]]; then
            printf "${RED}ERROR: No read permission for models directory: ${MODELS_DIR}${NC}\n"
            printf "${YELLOW}Please check directory permissions${NC}\n"
            validation_failed=true
        else
            printf "${GREEN}✓ Models directory exists and is readable${NC}\n"
            
            # Check for expected subdirectories (warn but don't fail)
            local model_subdirs=("Stable-diffusion" "Lora" "VAE" "text_encoder")
            local missing_subdirs=()
            for subdir in "${model_subdirs[@]}"; do
                if [[ ! -d "${MODELS_DIR}/${subdir}" ]]; then
                    missing_subdirs+=("$subdir")
                fi
            done
            
            if [[ ${#missing_subdirs[@]} -gt 0 ]]; then
                printf "${YELLOW}Warning: Some model subdirectories are missing:${NC}\n"
                for subdir in "${missing_subdirs[@]}"; do
                    printf "${YELLOW}  - ${subdir}${NC}\n"
                done
                printf "${BLUE}WebUI will create them as needed${NC}\n"
            fi
        fi
    else
        printf "${BLUE}No custom models directory specified - using WebUI default${NC}\n"
    fi
    
    # 2. Validate OUTPUT_DIR if specified
    if [[ -n "$OUTPUT_DIR" ]]; then
        printf "${BLUE}Checking output directory: ${OUTPUT_DIR}${NC}\n"
        
        if [[ ! -d "$OUTPUT_DIR" ]]; then
            if [[ "$AUTO_OUTPUT_VALIDATION" == "true" ]]; then
                printf "${YELLOW}Output directory does not exist: ${OUTPUT_DIR}${NC}\n"
                printf "${BLUE}Creating output directory...${NC}\n"
                
                if mkdir -p "$OUTPUT_DIR" 2>/dev/null; then
                    printf "${GREEN}✓ Successfully created output directory: ${OUTPUT_DIR}${NC}\n"
                else
                    printf "${RED}ERROR: Failed to create output directory: ${OUTPUT_DIR}${NC}\n"
                    printf "${YELLOW}Please check parent directory permissions${NC}\n"
                    validation_failed=true
                fi
            else
                printf "${RED}ERROR: Output directory does not exist: ${OUTPUT_DIR}${NC}\n"
                printf "${YELLOW}Solutions:${NC}\n"
                printf "  1. Create the directory: mkdir -p \"${OUTPUT_DIR}\"${NC}\n"
                printf "  2. Enable AUTO_OUTPUT_VALIDATION=true in forge-config.sh to auto-create${NC}\n"
                printf "  3. Fix the path in forge-config.sh${NC}\n"
                printf "  4. Remove OUTPUT_DIR setting to use WebUI default${NC}\n"
                validation_failed=true
            fi
        fi
        
        # Test write permissions if directory exists
        if [[ -d "$OUTPUT_DIR" ]]; then
            if [[ ! -w "$OUTPUT_DIR" ]]; then
                printf "${RED}ERROR: No write permission for output directory: ${OUTPUT_DIR}${NC}\n"
                printf "${YELLOW}Please check directory permissions${NC}\n"
                validation_failed=true
            else
                printf "${GREEN}✓ Output directory is writable${NC}\n"
                
                # Create subdirectories that WebUI expects (only if validation is enabled)
                if [[ "$AUTO_OUTPUT_VALIDATION" == "true" ]]; then
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
                fi
            fi
        fi
    else
        printf "${BLUE}No custom output directory specified - using WebUI default${NC}\n"
    fi
    
    # 3. Validate TEMP_CACHE_DIR if specified (critical - must exist)
    if [[ -n "$LOCAL_TEMP_DIR" ]]; then
        printf "${BLUE}Checking temp cache directory: ${LOCAL_TEMP_DIR}${NC}\n"
        
        if [[ ! -d "$LOCAL_TEMP_DIR" ]]; then
            printf "${RED}CRITICAL ERROR: Custom temp directory does not exist: ${LOCAL_TEMP_DIR}${NC}\n"
            printf "${YELLOW}Cannot proceed - temp directory is mandatory when configured.${NC}\n"
            printf "${YELLOW}Solutions:${NC}\n"
            printf "  1. Create the directory: mkdir -p \"${LOCAL_TEMP_DIR}\"${NC}\n"
            printf "  2. If using external/network drive, ensure it's mounted${NC}\n"
            printf "  3. Remove TEMP_CACHE_DIR from forge-config.sh to use system default${NC}\n"
            validation_failed=true
        elif [[ ! -w "$LOCAL_TEMP_DIR" ]]; then
            printf "${RED}CRITICAL ERROR: Custom temp directory is not writable: ${LOCAL_TEMP_DIR}${NC}\n"
            printf "${YELLOW}Cannot proceed - check permissions.${NC}\n"
            validation_failed=true
        else
            printf "${GREEN}✓ Temp cache directory exists and is writable${NC}\n"
        fi
    else
        printf "${BLUE}No custom temp directory configured - will use system default${NC}\n"
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

# Validation function for output directories (legacy - kept for compatibility)
validate_output_paths() {
    # This function is now handled by validate_all_paths() but kept for compatibility
    # In case any custom scripts call it directly
    if [[ "$AUTO_OUTPUT_VALIDATION" != "true" ]] || [[ -z "$OUTPUT_DIR" ]]; then
        return 0
    fi
    
    printf "${BLUE}Note: Output path validation is now handled by validate_all_paths()${NC}\n"
    return 0
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
        printf "${YELLOW}config.json not found - will be created on first run${NC}\n"
        return 0
    fi
    
    printf "${BLUE}Models directory: ${MODELS_DIR}${NC}\n"
    
    # Fix absolute model paths in config.json that point to old/wrong locations
    # This is a common issue when moving models directories
    if command -v python &> /dev/null; then
        printf "${BLUE}Checking for absolute model paths in config.json...${NC}\n"
        
        # Use Python to safely parse and update JSON
        python << EOF
import json
import os
import sys

config_file = "${config_file}"
models_dir = "${MODELS_DIR}"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    changed = False
    
    # Check forge_additional_modules for absolute paths
    if 'forge_additional_modules' in config and isinstance(config['forge_additional_modules'], list):
        old_modules = config['forge_additional_modules'][:]
        new_modules = []
        removed_modules = []
        
        for module_path in old_modules:
            if module_path and os.path.isabs(module_path):
                # This is an absolute path - check if it exists
                if not os.path.exists(module_path):
                    # Path doesn't exist - try to relocate it to new models directory
                    # Extract just the filename and subdirectory structure
                    # E.g., "/old/path/models/VAE/file.safetensors" -> "VAE/file.safetensors"
                    
                    # Find "models" in the path and take everything after it
                    parts = module_path.split(os.sep)
                    if 'models' in parts:
                        idx = parts.index('models')
                        relative_path = os.sep.join(parts[idx+1:])
                        new_path = os.path.join(models_dir, relative_path)
                        
                        if os.path.exists(new_path):
                            print(f"✓ Relocated: {relative_path}")
                            new_modules.append(new_path)
                            changed = True
                        else:
                            print(f"✗ Removed (not found in new location): {module_path}", file=sys.stderr)
                            removed_modules.append(module_path)
                            changed = True
                    else:
                        print(f"✗ Removed (invalid path structure): {module_path}", file=sys.stderr)
                        removed_modules.append(module_path)
                        changed = True
                else:
                    # Path exists, keep it but warn
                    new_modules.append(module_path)
            else:
                # Relative path or empty, keep it
                if module_path:  # Don't keep empty strings
                    new_modules.append(module_path)
        
        if changed:
            config['forge_additional_modules'] = new_modules
            
            # Write back to config.json
            with open(config_file, 'w') as f:
                json.dump(config, f, indent=4)
            
            print(f"Updated config.json with {len(new_modules)} module(s)")
            if removed_modules:
                print(f"Removed {len(removed_modules)} invalid module path(s)")
            sys.exit(0)  # Success with changes
        else:
            sys.exit(1)  # No changes needed
    else:
        sys.exit(1)  # No changes needed

except Exception as e:
    print(f"Error updating config.json: {e}", file=sys.stderr)
    sys.exit(2)  # Error
EOF
        
        PYTHON_EXIT_CODE=$?
        if [[ $PYTHON_EXIT_CODE -eq 0 ]]; then
            printf "${GREEN}✓ Updated config.json with corrected model paths${NC}\n"
        elif [[ $PYTHON_EXIT_CODE -eq 1 ]]; then
            printf "${GREEN}✓ No absolute path corrections needed${NC}\n"
        else
            printf "${YELLOW}Warning: Could not update config.json automatically${NC}\n"
        fi
    fi
    
    printf "${GREEN}✓ Models configuration synchronized${NC}\n"
}

# Configuration sync function for output directories
sync_output_config() {
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Synchronizing output directory configuration...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    local config_file="${WEBUI_DIR}/config.json"
    
    # Check if config.json exists
    if [[ ! -f "$config_file" ]]; then
        if [[ -n "$OUTPUT_DIR" ]]; then
            printf "${YELLOW}config.json not found - creating new configuration with custom output dir${NC}\n"
            
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
        else
            printf "${BLUE}config.json not found and no custom output dir - WebUI will create defaults${NC}\n"
        fi
        return 0
    fi
    
    # Sync output directories in existing config.json
    if command -v python &> /dev/null; then
        python << EOF
import json
import sys
import os

config_file = "${config_file}"
output_dir = "${OUTPUT_DIR}"
webui_dir = "${WEBUI_DIR}"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    changed = False
    
    if output_dir:
        # Custom output dir configured - set all output paths
        output_paths = {
            'outdir_txt2img_samples': f'{output_dir}/txt2img-images',
            'outdir_img2img_samples': f'{output_dir}/img2img-images',
            'outdir_extras_samples': f'{output_dir}/extras-images',
            'outdir_txt2img_grids': f'{output_dir}/txt2img-grids',
            'outdir_img2img_grids': f'{output_dir}/img2img-grids',
            'outdir_save': f'{output_dir}/saved'
        }
        
        for key, value in output_paths.items():
            if config.get(key) != value:
                config[key] = value
                changed = True
        
        if changed:
            print(f"✓ Updated output directories to: {output_dir}")
        else:
            print(f"✓ Output directories already set to: {output_dir}")
    else:
        # No custom output dir - restore empty strings (WebUI default behavior)
        output_keys = [
            'outdir_txt2img_samples',
            'outdir_img2img_samples', 
            'outdir_extras_samples',
            'outdir_txt2img_grids',
            'outdir_img2img_grids',
            'outdir_save'
        ]
        
        for key in output_keys:
            if config.get(key, ''):
                config[key] = ''
                changed = True
        
        if changed:
            print("✓ Restored default output directories (WebUI defaults)")
        else:
            print("✓ Output directories already at defaults")
    
    if changed:
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=4)
        sys.exit(0)
    else:
        sys.exit(1)

except Exception as e:
    print(f"Warning: Could not update config.json: {e}", file=sys.stderr)
    sys.exit(2)
EOF
        
        PYTHON_EXIT_CODE=$?
        if [[ $PYTHON_EXIT_CODE -eq 0 ]] || [[ $PYTHON_EXIT_CODE -eq 1 ]]; then
            printf "${GREEN}✓ config.json output directories synchronized${NC}\n"
        else
            printf "${YELLOW}Warning: Could not update config.json${NC}\n"
        fi
    else
        printf "${BLUE}Python unavailable - skipping config.json sync${NC}\n"
    fi
}

# Set up cleanup trap for script exit
cleanup_on_exit() {
    printf "\n${YELLOW}Stable Diffusion WebUI Forge Classic is shutting down...${NC}\n"
    cleanup_cache
    printf "${GREEN}Cleanup completed. Goodbye!${NC}\n"
}

# Register cleanup function to run on script exit
trap cleanup_on_exit EXIT INT TERM

# Set up temporary directories for the APPLICATION (not launcher operations)
# GRADIO_TEMP_DIR is what Forge Classic's ui_tempdir.py checks for (priority #1)
# TMPDIR is the standard Unix environment variable (fallback)
# Note: Path validation was already done by validate_all_paths()
if [[ -n "$LOCAL_TEMP_DIR" ]]; then
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Configuring custom temp directory for application...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Create the directory if needed (should already exist from validation)
    mkdir -p "${LOCAL_TEMP_DIR}" 2>/dev/null || true
    
    # Set environment variables for the APPLICATION
    export TMPDIR="${LOCAL_TEMP_DIR}"
    export GRADIO_TEMP_DIR="${LOCAL_TEMP_DIR}"
    
    printf "${GREEN}✓ Custom temp directory configured:${NC}\n"
    printf "  Directory: ${LOCAL_TEMP_DIR}\n"
    printf "  TMPDIR: ${TMPDIR}\n"
    printf "  GRADIO_TEMP_DIR: ${GRADIO_TEMP_DIR}\n"
    printf "${GREEN}✓ Application will use this directory${NC}\n"
    printf "${BLUE}Note: Launcher operations (compiling, etc.) may use system temp${NC}\n"
else
    printf "${BLUE}No custom temp directory configured - application will use default behavior${NC}\n"
fi

# Set environment variables for Forge Classic compatibility
# Let Forge Classic handle all package management including PyTorch
printf "${GREEN}Allowing Forge Classic to manage all packages inside conda environment${NC}\n"
printf "${BLUE}Forge Classic will install PyTorch and other packages as needed${NC}\n"

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
        
        # Check for RTX 50-series (Blackwell) and auto-detect optimal SageAttention version
        if command -v nvidia-smi &> /dev/null; then
            GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
            if [[ -n "$GPU_NAME" ]]; then
                printf "${BLUE}GPU Model: ${GPU_NAME}${NC}\n"
                
                # Check if it's an RTX 50-series Blackwell GPU
                if [[ "$GPU_NAME" =~ RTX[[:space:]]50[7-9]0 ]]; then
                    printf "${YELLOW}═══════════════════════════════════════════════════════════${NC}\n"
                    printf "${GREEN}🚀 Blackwell GPU Detected! (RTX 50-series)${NC}\n"
                    
                    # Check Python version from environment file (SageAttention3 requires Python 3.13+)
                    ENV_PYTHON_VERSION=""
                    if [[ -f "${SCRIPT_DIR}/${CONDA_ENV_FILE}" ]]; then
                        ENV_PYTHON_VERSION=$(grep -E "^[[:space:]]*-[[:space:]]*python=" "${SCRIPT_DIR}/${CONDA_ENV_FILE}" | head -n1 | sed -E 's/.*python=([0-9]+\.[0-9]+).*/\1/' || echo "")
                    fi
                    
                    # Check if Python version supports SageAttention3 (requires 3.13+)
                    PYTHON_SUPPORTS_SAGE3=false
                    if [[ -n "$ENV_PYTHON_VERSION" ]]; then
                        # Extract major.minor version
                        PYTHON_MAJOR=$(echo "$ENV_PYTHON_VERSION" | cut -d. -f1)
                        PYTHON_MINOR=$(echo "$ENV_PYTHON_VERSION" | cut -d. -f2)
                        # Check if version is 3.13 or higher
                        if [[ "$PYTHON_MAJOR" -gt 3 ]] || [[ "$PYTHON_MAJOR" -eq 3 && "$PYTHON_MINOR" -ge 13 ]]; then
                            PYTHON_SUPPORTS_SAGE3=true
                        fi
                    fi
                    
                    # Handle version selection based on config and flags
                    if [[ "$SAGE_VERSION_EXPLICIT" == "true" ]]; then
                        # User explicitly set version via --sage2 or --sage3
                        if [[ "$SAGE_VERSION" == "3" ]]; then
                            if [[ "$PYTHON_SUPPORTS_SAGE3" == "false" ]] && [[ -n "$ENV_PYTHON_VERSION" ]]; then
                                printf "${RED}⚠ WARNING: SageAttention3 requires Python 3.13+, but environment has Python ${ENV_PYTHON_VERSION}${NC}\n"
                                printf "${YELLOW}   Falling back to SageAttention 2.2.0${NC}\n"
                                SAGE_VERSION="2"
                            else
                                printf "${GREEN}✓ Using SageAttention3 (explicit --sage3 flag)${NC}\n"
                            fi
                        else
                            printf "${YELLOW}💡 Note: Using SageAttention 2 (explicit --sage2 flag)${NC}\n"
                            if [[ "$PYTHON_SUPPORTS_SAGE3" == "true" ]]; then
                                printf "${YELLOW}   Your GPU supports SageAttention3 for better performance${NC}\n"
                            fi
                        fi
                    elif [[ "$SAGE_VERSION" == "auto" ]]; then
                        # Auto-detect: Switch to SageAttention3 for Blackwell, but only if Python 3.13+
                        if [[ "$PYTHON_SUPPORTS_SAGE3" == "true" ]]; then
                            SAGE_VERSION="3"
                            printf "${GREEN}✓ Auto-detected: Using SageAttention3 (FP4 Tensor Cores)${NC}\n"
                            printf "${BLUE}   Optimized for Blackwell architecture - up to 5x faster${NC}\n"
                            printf "${YELLOW}   To always use v2, set DEFAULT_SAGE_VERSION=\"2\" in config${NC}\n"
                            printf "${YELLOW}   To use v2 once, run with: --sage2${NC}\n"
                        else
                            SAGE_VERSION="2"
                            printf "${YELLOW}⚠ Auto-detection: Blackwell GPU detected, but Python ${ENV_PYTHON_VERSION:-unknown} < 3.13${NC}\n"
                            printf "${YELLOW}   SageAttention3 requires Python 3.13+ - using SageAttention 2.2.0 instead${NC}\n"
                            printf "${BLUE}   SageAttention 2.2.0 still provides 2-5x speedup${NC}\n"
                            printf "${YELLOW}   To use SageAttention3, upgrade to Python 3.13 in ${CONDA_ENV_FILE}${NC}\n"
                        fi
                    elif [[ "$SAGE_VERSION" == "3" ]]; then
                        # Config explicitly set to v3
                        if [[ "$PYTHON_SUPPORTS_SAGE3" == "false" ]] && [[ -n "$ENV_PYTHON_VERSION" ]]; then
                            printf "${RED}⚠ WARNING: SageAttention3 requires Python 3.13+, but environment has Python ${ENV_PYTHON_VERSION}${NC}\n"
                            printf "${YELLOW}   Falling back to SageAttention 2.2.0${NC}\n"
                            SAGE_VERSION="2"
                        else
                            printf "${GREEN}✓ Using SageAttention3 (DEFAULT_SAGE_VERSION=\"3\" in config)${NC}\n"
                        fi
                    else
                        # Config explicitly set to v2
                        printf "${YELLOW}💡 Note: Using SageAttention 2 (DEFAULT_SAGE_VERSION=\"2\" in config)${NC}\n"
                        if [[ "$PYTHON_SUPPORTS_SAGE3" == "true" ]]; then
                            printf "${YELLOW}   Your GPU supports SageAttention3 for better performance${NC}\n"
                        fi
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
printf "${GREEN}Activating conda environment for Stable Diffusion WebUI Forge Classic...${NC}\n"
printf "%s\n" "${delimiter}"

eval "$("${CONDA_EXE}" shell.bash hook)"
conda activate "${ENV_NAME}"

if [[ $? -ne 0 ]]; then
    printf "\n${RED}ERROR: Failed to activate conda environment '${ENV_NAME}'${NC}\n"
    exit 1
fi


# Verify package versions match requirements
verify_package_versions

# Helper function to compile SageAttention from source
install_sageattention_from_source() {
    local purpose="$1"  # "install" or "upgrade"
    
    SAGE_DIR="/tmp/SageAttention_forge"
    if [[ -d "$SAGE_DIR" ]]; then
        rm -rf "$SAGE_DIR"
    fi
    
    printf "${BLUE}Cloning SageAttention repository...${NC}\n"
    git clone https://github.com/thu-ml/SageAttention.git "$SAGE_DIR"
    if [[ $? -ne 0 ]]; then
        printf "${RED}✗ Failed to clone SageAttention repository${NC}\n"
        printf "${YELLOW}Check your internet connection${NC}\n"
        return 1
    fi
    
    # Detect CPU cores and set parallel compilation
    NPROC=$(nproc)
    # Use 75% of cores (leave some for system), minimum 4, maximum 16
    PARALLEL_JOBS=$(( NPROC * 3 / 4 ))
    PARALLEL_JOBS=$(( PARALLEL_JOBS < 4 ? 4 : PARALLEL_JOBS ))
    PARALLEL_JOBS=$(( PARALLEL_JOBS > 16 ? 16 : PARALLEL_JOBS ))
    
    printf "${BLUE}Detected ${NPROC} CPU cores, using ${PARALLEL_JOBS} parallel jobs${NC}\n"
    
    # Set parallel compilation environment variables
    export MAX_JOBS="${PARALLEL_JOBS}"
    export CMAKE_BUILD_PARALLEL_LEVEL="${PARALLEL_JOBS}"
    export NVCC_APPEND_FLAGS="--threads ${PARALLEL_JOBS}"
    export CUDA_HOME="${CONDA_PREFIX}"
    export VERBOSE="1"
    
    printf "${BLUE}Compiling SageAttention from source (this may take several minutes)...${NC}\n"
    printf "${BLUE}Using CUDA_HOME: ${CUDA_HOME}${NC}\n"
    printf "${BLUE}Build directory: ${SAGE_DIR}${NC}\n"
    
    # Handle version-specific installation
    if [[ "$SAGE_VERSION" == "3" ]]; then
        # SageAttention3 - navigate to blackwell subdirectory
        cd "$SAGE_DIR/sageattention3_blackwell"
        export TORCH_CUDA_ARCH_LIST="8.0;9.0"  # Both Ampere/Ada and Blackwell
        printf "${GREEN}Installing from sageattention3_blackwell subdirectory${NC}\n"
        
        # First, uninstall any existing versions
        printf "${BLUE}Removing old SageAttention versions...${NC}\n"
        pip uninstall -y sageattention sageattn3 2>/dev/null || true
        
        # Compile directly with setup.py
        printf "${BLUE}Compiling SageAttention3 with setup.py install...${NC}\n"
        # Use set -o pipefail to capture actual exit code through tee
        set -o pipefail
        python setup.py install 2>&1 | tee /tmp/sageattention3_forge_build.log
        local result=$?
        set +o pipefail
    else
        # SageAttention 2.2.0 - use root directory
        cd "$SAGE_DIR"
        
        # Auto-detect GPU architectures for compilation
        DETECTED_ARCHS=()
        if command -v nvidia-smi &> /dev/null; then
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
                    esac
                fi
            done < <(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | sort -u)
            
            if [[ ${#DETECTED_ARCHS[@]} -gt 0 ]]; then
                UNIQUE_ARCHS=($(printf '%s\n' "${DETECTED_ARCHS[@]}" | sort -u))
                AUTO_TORCH_CUDA_ARCH_LIST=$(IFS=';'; echo "${UNIQUE_ARCHS[*]}")
            else
                AUTO_TORCH_CUDA_ARCH_LIST="8.0;8.9"
            fi
        else
            AUTO_TORCH_CUDA_ARCH_LIST="8.0;8.9"
        fi
        
        export TORCH_CUDA_ARCH_LIST="${AUTO_TORCH_CUDA_ARCH_LIST}"
        printf "${BLUE}Compiling SageAttention 2.2.0 for architectures: ${TORCH_CUDA_ARCH_LIST}${NC}\n"
        
        # First, uninstall any existing versions
        printf "${BLUE}Removing old SageAttention versions...${NC}\n"
        pip uninstall -y sageattention 2>/dev/null || true
        
        # Compile directly with setup.py
        printf "${BLUE}Compiling SageAttention 2.2.0 with setup.py install...${NC}\n"
        # Use set -o pipefail to capture actual exit code through tee
        set -o pipefail
        python setup.py install 2>&1 | tee /tmp/sageattention_build.log
        local result=$?
        set +o pipefail
    fi
    
    cd "${WEBUI_DIR}"
    
    if [[ $result -eq 0 ]]; then
        if [[ "$SAGE_VERSION" == "3" ]]; then
            printf "${GREEN}✓ Build log saved to: /tmp/sageattention3_forge_build.log${NC}\n"
        else
            printf "${GREEN}✓ Build log saved to: /tmp/sageattention_build.log${NC}\n"
        fi
        rm -rf "$SAGE_DIR"
        
        if [[ "$purpose" == "upgrade" ]]; then
            printf "${GREEN}✓ Successfully upgraded SageAttention from source${NC}\n"
            printf "${YELLOW}Please restart Forge Classic to use the new version${NC}\n"
        else
            printf "${GREEN}✓ Successfully installed SageAttention from source${NC}\n"
        fi
        return 0
    else
        printf "${RED}✗ Failed to compile SageAttention${NC}\n"
        printf "${RED}Exit code: ${result}${NC}\n"
        
        # Check build log for specific error messages
        local build_log=""
        if [[ "$SAGE_VERSION" == "3" ]]; then
            build_log="/tmp/sageattention3_forge_build.log"
        else
            build_log="/tmp/sageattention_build.log"
        fi
        
        if [[ -f "$build_log" ]]; then
            if grep -q "ModuleNotFoundError.*torch" "$build_log" 2>/dev/null; then
                printf "${YELLOW}Root cause: PyTorch is not installed${NC}\n"
                printf "${YELLOW}Solution: Install PyTorch first, then retry SageAttention compilation${NC}\n"
            elif grep -q "CUDA" "$build_log" 2>/dev/null; then
                printf "${YELLOW}Root cause: CUDA-related error${NC}\n"
                printf "${YELLOW}Check CUDA installation and version compatibility${NC}\n"
            else
                printf "${YELLOW}Check build log for details:${NC}\n"
                printf "${BLUE}  tail -50 ${build_log}${NC}\n"
            fi
        fi
        
        printf "${YELLOW}Build log saved to: ${build_log}${NC}\n"
        printf "${YELLOW}Build directory preserved at: ${SAGE_DIR}${NC}\n"
        printf "${YELLOW}Common issues:${NC}\n"
        printf "  1. Check build log: cat ${build_log} | tail -100${NC}\n"
        printf "  2. Verify PyTorch is installed: python -c 'import torch; print(torch.__version__)'${NC}\n"
        printf "  3. Verify CUDA libraries: ls -la ${CONDA_PREFIX}/lib/libcudart*${NC}\n"
        printf "  4. Check for library conflicts in conda env${NC}\n"
        # Don't remove SAGE_DIR on failure for debugging
        return 1
    fi
}

# SageAttention version check and upgrade function
check_sageattention_version() {
    # Skip if SageAttention is disabled
    if [[ "$DEFAULT_ENABLE_SAGE" != "true" ]]; then
        return 0
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Checking SageAttention version...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Check if SageAttention is actually installed and working
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
    print('NOT_INSTALLED')
" 2>/dev/null)
    
    if [[ "$installed_version" == "NOT_INSTALLED" ]]; then
        printf "${YELLOW}SageAttention is not installed${NC}\n"
        printf "${BLUE}Will install version ${SAGE_VERSION} based on GPU detection${NC}\n"
        
        if [[ "$AUTO_UPGRADE_SAGE" == "true" ]]; then
            printf "${GREEN}AUTO_UPGRADE_SAGE=true, installing SageAttention from source...${NC}\n"
            install_sageattention_from_source "install"
            if [[ $? -ne 0 ]]; then
                printf "${YELLOW}Continuing without SageAttention (will use PyTorch attention)${NC}\n"
            fi
        else
            printf "${YELLOW}Would you like to install SageAttention from source? [y/N]: ${NC}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                install_sageattention_from_source "install"
                if [[ $? -ne 0 ]]; then
                    printf "${YELLOW}Continuing without SageAttention (will use PyTorch attention)${NC}\n"
                fi
            else
                printf "${BLUE}Skipping SageAttention installation${NC}\n"
            fi
        fi
    elif [[ "$installed_version" =~ ^1\. ]]; then
        printf "${YELLOW}Outdated SageAttention 1.x detected${NC}\n"
        printf "  Installed: ${installed_version}\n"
        printf "  Recommended: 2.x or 3.x (based on GPU)\n"
        
        # Provide context about version differences
        if true; then
            printf "\n${BLUE}SageAttention 2.x provides significant improvements over 1.x:${NC}\n"
            printf "  • 2-5x faster attention computation\n"
            printf "  • Per-thread quantization\n"
            printf "  • Outlier smoothing\n"
            printf "  • Better CUDA kernel optimization\n"
        fi
        
        if [[ "$AUTO_UPGRADE_SAGE" == "true" ]]; then
            printf "\n${GREEN}AUTO_UPGRADE_SAGE=true, upgrading SageAttention from source...${NC}\n"
            install_sageattention_from_source "upgrade"
            if [[ $? -ne 0 ]]; then
                printf "${YELLOW}Continuing with version ${installed_version}${NC}\n"
            fi
        else
            printf "\n${YELLOW}Would you like to upgrade SageAttention from source? [y/N]: ${NC}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                install_sageattention_from_source "upgrade"
                if [[ $? -ne 0 ]]; then
                    printf "${YELLOW}Continuing with version ${installed_version}${NC}\n"
                fi
            else
                printf "${BLUE}Continuing with installed version ${installed_version}${NC}\n"
                printf "${YELLOW}Note: You may not get optimal performance${NC}\n"
                printf "${YELLOW}To auto-upgrade in future, set AUTO_UPGRADE_SAGE=true in forge-config.sh${NC}\n"
            fi
        fi
    else
        printf "${GREEN}✓ SageAttention ${installed_version} is installed (matches desired version)${NC}\n"
    fi
}

check_sageattention_version

# Validate all configured paths before proceeding
validate_all_paths

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

# Synchronize temp directory in config.json
# If custom temp is configured: set it
# If custom temp is NOT configured: remove it (restore default behavior)
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Synchronizing temp directory in config.json...${NC}\n"
printf "%s\n" "${delimiter}"

config_file="${WEBUI_DIR}/config.json"

if [[ -f "$config_file" ]] && command -v python &> /dev/null; then
    python << EOF
import json
import sys
import os

config_file = "${config_file}"
temp_dir = "${LOCAL_TEMP_DIR}"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    old_temp_dir = config.get('temp_dir', '')
    
    # Get the default temp dir that WebUI would use
    # From shared_options.py: os.path.join(data_path, "tmp")
    default_temp_dir = os.path.join(os.path.dirname(config_file), "tmp")
    
    changed = False
    
    if temp_dir:
        # Custom temp dir is configured - set it
        if old_temp_dir != temp_dir:
            config['temp_dir'] = temp_dir
            changed = True
            if old_temp_dir:
                print(f"✓ Updated temp_dir: {old_temp_dir} → {temp_dir}")
            else:
                print(f"✓ Set temp_dir: {temp_dir}")
    else:
        # Custom temp dir is NOT configured - restore default
        if old_temp_dir and old_temp_dir != default_temp_dir:
            config['temp_dir'] = default_temp_dir
            changed = True
            print(f"✓ Restored default temp_dir: {old_temp_dir} → {default_temp_dir}")
        elif not old_temp_dir:
            print(f"✓ temp_dir not set (using WebUI default behavior)")
        else:
            print(f"✓ temp_dir already at default: {default_temp_dir}")
    
    if changed:
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=4)
        sys.exit(0)
    else:
        sys.exit(1)

except Exception as e:
    print(f"Warning: Could not update config.json: {e}", file=sys.stderr)
    sys.exit(2)
EOF
    
    PYTHON_EXIT_CODE=$?
    if [[ $PYTHON_EXIT_CODE -eq 0 ]] || [[ $PYTHON_EXIT_CODE -eq 1 ]]; then
        printf "${GREEN}✓ config.json temp_dir synchronized${NC}\n"
    else
        printf "${YELLOW}Warning: Could not update config.json${NC}\n"
    fi
else
    printf "${BLUE}config.json not found or python unavailable - skipping sync${NC}\n"
fi

# Synchronize models directory configuration
sync_models_config

# Configure Qwen sigma shift if specified
configure_qwen_shift() {
    local qwen_config="${WEBUI_DIR}/backend/huggingface/Qwen/Qwen-Image/scheduler/scheduler_config.json"
    
    # Only proceed if config file exists
    if [[ ! -f "$qwen_config" ]]; then
        return 0
    fi
    
    # If QWEN_SIGMA_SHIFT is empty, don't modify the file
    if [[ -z "$QWEN_SIGMA_SHIFT" ]]; then
        return 0
    fi
    
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Configuring Qwen sigma shift...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    # Use Python to safely update the JSON
    python << EOF
import json
import sys

config_file = "${qwen_config}"
shift_value = "${QWEN_SIGMA_SHIFT}"

try:
    # Validate shift value is a number
    shift_float = float(shift_value)
    
    # Read the config
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    # Update shift value
    old_shift = config.get('shift', 1.0)
    config['shift'] = shift_float
    
    # Write back
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print(f"✓ Updated Qwen sigma shift: {old_shift} → {shift_float}")
    sys.exit(0)
    
except ValueError:
    print(f"✗ Invalid shift value: ${QWEN_SIGMA_SHIFT} (must be a number)", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"✗ Error updating config: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    if [[ $? -eq 0 ]]; then
        printf "${GREEN}✓ Qwen sigma shift configured${NC}\n"
    else
        printf "${YELLOW}Warning: Could not update Qwen sigma shift${NC}\n"
    fi
}

configure_qwen_shift

# Browser auto-launch configuration sync function
sync_browser_config() {
    printf "\n%s\n" "${delimiter}"
    printf "${GREEN}Synchronizing browser auto-launch configuration...${NC}\n"
    printf "%s\n" "${delimiter}"
    
    local config_file="${WEBUI_DIR}/config.json"
    
    # Check if config.json exists
    if [[ ! -f "$config_file" ]]; then
        printf "${YELLOW}config.json not found - will be created on first run${NC}\n"
        return 0
    fi
    
    printf "${BLUE}Browser auto-launch setting: ${AUTO_LAUNCH_BROWSER}${NC}\n"
    
    # Sync browser setting in existing config.json
    if command -v python &> /dev/null; then
        python << EOF
import json
import sys

config_file = "${config_file}"
auto_launch_setting = "${AUTO_LAUNCH_BROWSER}"

# Validate the setting
valid_options = ["Disable", "Local", "Remote"]
if auto_launch_setting not in valid_options:
    print(f"Warning: Invalid AUTO_LAUNCH_BROWSER value '{auto_launch_setting}'", file=sys.stderr)
    print(f"Valid options: {', '.join(valid_options)}", file=sys.stderr)
    print(f"Using default: Disable", file=sys.stderr)
    auto_launch_setting = "Disable"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    old_setting = config.get('auto_launch_browser', 'not set')
    
    if old_setting != auto_launch_setting:
        config['auto_launch_browser'] = auto_launch_setting
        
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=4)
        
        print(f"✓ Updated auto_launch_browser: {old_setting} → {auto_launch_setting}")
        sys.exit(0)
    else:
        print(f"✓ auto_launch_browser already set to: {auto_launch_setting}")
        sys.exit(1)

except Exception as e:
    print(f"Warning: Could not update config.json: {e}", file=sys.stderr)
    sys.exit(2)
EOF
        
        PYTHON_EXIT_CODE=$?
        if [[ $PYTHON_EXIT_CODE -eq 0 ]] || [[ $PYTHON_EXIT_CODE -eq 1 ]]; then
            printf "${GREEN}✓ Browser auto-launch configuration synchronized${NC}\n"
        else
            printf "${YELLOW}Warning: Could not update browser config in config.json${NC}\n"
        fi
    else
        printf "${BLUE}Python unavailable - skipping browser config sync${NC}\n"
    fi
}

sync_browser_config

# Launch the application
printf "\n%s\n" "${delimiter}"
printf "${GREEN}Launching Stable Diffusion WebUI Forge Classic...${NC}\n"
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

# Set CUDA_HOME to conda environment for JIT compilation of CUDA extensions
# This is critical for libraries that compile CUDA code on-the-fly
if [[ -n "${CONDA_PREFIX}" ]]; then
    export CUDA_HOME="${CONDA_PREFIX}"
    export CUDA_PATH="${CONDA_PREFIX}"
    
    # Conda CUDA toolkit installs headers in targets/x86_64-linux/include
    if [[ -d "${CONDA_PREFIX}/targets/x86_64-linux/include" ]]; then
        export CPLUS_INCLUDE_PATH="${CONDA_PREFIX}/targets/x86_64-linux/include${CPLUS_INCLUDE_PATH:+:${CPLUS_INCLUDE_PATH}}"
        export C_INCLUDE_PATH="${CONDA_PREFIX}/targets/x86_64-linux/include${C_INCLUDE_PATH:+:${C_INCLUDE_PATH}}"
        export CPPFLAGS="-I${CONDA_PREFIX}/targets/x86_64-linux/include ${CPPFLAGS}"
    fi
    
    printf "${BLUE}Setting CUDA_HOME to conda environment: ${CUDA_HOME}${NC}\n"
fi

# Detect GPU compute capability and set TORCH_CUDA_ARCH_LIST for JIT compilation
if command -v nvidia-smi &> /dev/null; then
    GPU_COMPUTE_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 | tr -d ' ')
    if [[ -n "$GPU_COMPUTE_CAP" ]]; then
        case "$GPU_COMPUTE_CAP" in
            8.0|8.6|8.9)
                export TORCH_CUDA_ARCH_LIST="8.0;8.9"
                printf "${BLUE}Detected GPU compute capability: ${GPU_COMPUTE_CAP} (RTX 30xx/40xx series)${NC}\n"
                printf "${BLUE}Setting TORCH_CUDA_ARCH_LIST=8.0;8.9 for CUDA extension compilation${NC}\n"
                ;;
            9.0)
                export TORCH_CUDA_ARCH_LIST="9.0"
                printf "${BLUE}Detected GPU compute capability: ${GPU_COMPUTE_CAP} (Hopper H100)${NC}\n"
                printf "${BLUE}Setting TORCH_CUDA_ARCH_LIST=9.0 for CUDA extension compilation${NC}\n"
                ;;
            10.*)
                export TORCH_CUDA_ARCH_LIST="9.0;10.0"
                printf "${BLUE}Detected GPU compute capability: ${GPU_COMPUTE_CAP} (Blackwell RTX 50xx)${NC}\n"
                printf "${BLUE}Setting TORCH_CUDA_ARCH_LIST=9.0;10.0 for CUDA extension compilation${NC}\n"
                ;;
            *)
                export TORCH_CUDA_ARCH_LIST="8.0;8.9"
                printf "${YELLOW}Unknown GPU compute capability: ${GPU_COMPUTE_CAP}, defaulting to TORCH_CUDA_ARCH_LIST=8.0;8.9${NC}\n"
                ;;
        esac
    fi
fi

# Set up restart marker location
# If custom temp is configured, use it; otherwise use WebUI's tmp directory
if [[ -n "$LOCAL_TEMP_DIR" ]]; then
    # Use custom temp directory for restart marker
    RESTART_DIR="${LOCAL_TEMP_DIR}/forge-restart"
    mkdir -p "${RESTART_DIR}"
    export SD_WEBUI_RESTART="${RESTART_DIR}/restart"
    printf "${GREEN}Restart marker location: ${SD_WEBUI_RESTART}${NC}\n"
else
    # Use WebUI's tmp directory for restart marker (default behavior)
    mkdir -p "${WEBUI_DIR}/tmp"
    export SD_WEBUI_RESTART="tmp/restart"
    printf "${GREEN}Restart marker location: ${WEBUI_DIR}/${SD_WEBUI_RESTART}${NC}\n"
fi

# Set up restart loop (from original script)
KEEP_GOING=1

while [[ "$KEEP_GOING" -eq "1" ]]; do
    # Launch the application with all passed arguments
    # --no-hashing skips model file verification for faster startup
    # --cuda-malloc enables CUDA memory allocation
    # Browser will not auto-launch (default behavior, --autolaunch not used)
    # Build launch arguments
    LAUNCH_ARGS=(--no-hashing --cuda-malloc)
    
    # Add SageAttention if not disabled
    if [[ "$DISABLE_SAGE" != "true" ]]; then
        LAUNCH_ARGS+=(--sage)
        printf "${GREEN}Using SageAttention for optimized attention computation${NC}\n"
    else
        LAUNCH_ARGS+=(--disable-sage)
        printf "${BLUE}SageAttention disabled - using PyTorch attention${NC}\n"
    fi
    
    # Force text encoders to CPU for large models like Qwen (saves GPU memory)
    LAUNCH_ARGS+=(--clip-in-cpu)
    printf "${BLUE}Text encoders will run on CPU to save GPU memory${NC}\n"
    printf "${BLUE}Browser will not open automatically (default behavior)${NC}\n"
    
    # Add models directory if specified (use correct argument for neo branch)
    if [[ -n "$MODELS_DIR" ]]; then
        LAUNCH_ARGS+=(--ckpt-dirs "$MODELS_DIR/Stable-diffusion")
        LAUNCH_ARGS+=(--lora-dirs "$MODELS_DIR/Lora")
        LAUNCH_ARGS+=(--vae-dirs "$MODELS_DIR/VAE")
        LAUNCH_ARGS+=(--text-encoder-dirs "$MODELS_DIR/text_encoder")
    fi
    
    # Launch Forge Classic - it will manage packages intelligently
    "${python_cmd}" -u launch.py "${LAUNCH_ARGS[@]}" "$@"
    
    if [[ ! -f tmp/restart ]]; then
        KEEP_GOING=0
    fi
done

printf "\n%s\n" "${delimiter}"
printf "${GREEN}Stable Diffusion WebUI Forge Classic session ended${NC}\n"
printf "%s\n" "${delimiter}"
