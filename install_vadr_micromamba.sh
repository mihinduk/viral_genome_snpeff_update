#!/bin/bash
# VADR Installation Script using Micromamba
# Version: 2.0.0 - Lightweight micromamba approach for viral annotation
#
# This script installs VADR (Viral Annotation DefineR) using micromamba
# which is more efficient than conda/mamba for dependency resolution.

set -e

SCRIPT_VERSION="2.0.0"

echo "========================================="
echo "VADR Installation Script (Micromamba)"
echo "Version: $SCRIPT_VERSION"
echo "========================================="
echo ""
echo "VADR (Viral Annotation DefineR) validates and annotates viral genomes"
echo "using covariance models and transfers annotations between related viruses."
echo ""

# Check if installation path provided
if [ -z "$1" ]; then
    echo "Usage: $0 <installation_path> [--check-only] [--force-reinstall]"
    echo ""
    echo "Examples:"
    echo "  $0 /ref/sahlab/software"
    echo "  $0 /opt/vadr --check-only"
    echo "  $0 /scratch/user/software --force-reinstall"
    echo ""
    echo "This script will install in the specified directory:"
    echo "  - Micromamba: <path>/micromamba"
    echo "  - VADR environment: <path>/envs/vadr_env"
    echo "  - Viral models: <path>/envs/vadr_env/share/vadr-*/vadr-models"
    echo "  - Wrapper scripts: <path>/vadr_wrappers/"
    echo ""
    echo "Options:"
    echo "  --check-only        Only check if VADR is installed, don't install"
    echo "  --force-reinstall   Remove existing installation and reinstall"
    echo ""
    echo "Requirements:"
    echo "  - Internet access for downloads"
    echo "  - ~2GB free space for VADR and models"
    echo "  - Write permissions to installation directory"
    echo ""
    echo "After installation, VADR can be used via:"
    echo "  <path>/micromamba run -p <path>/envs/vadr_env v-annotate.pl --help"
    exit 1
fi

INSTALL_DIR="$1"
CHECK_ONLY=false
FORCE_REINSTALL=false

# Parse additional arguments
for arg in "$@"; do
    case $arg in
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --force-reinstall)
            FORCE_REINSTALL=true
            shift
            ;;
    esac
done

echo "Installation directory: $INSTALL_DIR"
[ "$CHECK_ONLY" = true ] && echo "Mode: Check only (no installation)"
[ "$FORCE_REINSTALL" = true ] && echo "Mode: Force reinstall (remove existing)"

# Track installation status
INSTALL_SUMMARY=""

# Function to add to summary
add_to_summary() {
    INSTALL_SUMMARY="${INSTALL_SUMMARY}$1\n"
}

# Function to check if directory is writable
check_directory_permissions() {
    echo ""
    echo "=== Checking Installation Directory ==="
    
    # Check if directory exists
    if [ ! -d "$INSTALL_DIR" ]; then
        if [ "$CHECK_ONLY" = true ]; then
            echo "✗ Directory does not exist: $INSTALL_DIR"
            add_to_summary "✗ Directory: NOT FOUND"
            return 1
        else
            echo "Creating installation directory: $INSTALL_DIR"
            mkdir -p "$INSTALL_DIR" || {
                echo "✗ Failed to create directory: $INSTALL_DIR"
                echo "  Please check permissions or create manually"
                add_to_summary "✗ Directory: CREATION FAILED"
                exit 1
            }
            echo "✓ Created directory: $INSTALL_DIR"
        fi
    fi
    
    # Check write permissions
    if [ -w "$INSTALL_DIR" ]; then
        echo "✓ Directory is writable: $INSTALL_DIR"
        add_to_summary "✓ Directory: $INSTALL_DIR (writable)"
    else
        echo "✗ No write permissions for: $INSTALL_DIR"
        add_to_summary "✗ Directory: NO WRITE PERMISSIONS"
        exit 1
    fi
    
    # Check available space (need at least 2GB)
    AVAILABLE_SPACE=$(df -BG "$INSTALL_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$AVAILABLE_SPACE" -lt 2 ]; then
        echo "⚠ Low disk space: ${AVAILABLE_SPACE}GB available (2GB recommended)"
        add_to_summary "⚠ Disk space: ${AVAILABLE_SPACE}GB (may be insufficient)"
    else
        echo "✓ Sufficient disk space: ${AVAILABLE_SPACE}GB available"
    fi
}

# Function to check/install micromamba
install_micromamba() {
    echo ""
    echo "=== Installing Micromamba ==="
    
    MICROMAMBA_PATH="$INSTALL_DIR/micromamba"
    
    if [ -f "$MICROMAMBA_PATH" ]; then
        if [ "$FORCE_REINSTALL" = true ]; then
            echo "Removing existing micromamba (--force-reinstall)..."
            rm -f "$MICROMAMBA_PATH"
        else
            echo "✓ Micromamba already installed at: $MICROMAMBA_PATH"
            MICROMAMBA_VERSION=$("$MICROMAMBA_PATH" --version 2>/dev/null | head -n1 || echo "unknown")
            echo "  Version: $MICROMAMBA_VERSION"
            add_to_summary "✓ Micromamba: $MICROMAMBA_VERSION"
            return 0
        fi
    fi
    
    if [ "$CHECK_ONLY" = true ]; then
        echo "✗ Micromamba not found at: $MICROMAMBA_PATH"
        add_to_summary "✗ Micromamba: NOT INSTALLED"
        return 1
    fi
    
    echo "Downloading micromamba..."
    cd "$INSTALL_DIR"
    
    # Detect architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        MICROMAMBA_URL="https://micro.mamba.pm/api/micromamba/linux-64/latest"
    elif [ "$ARCH" = "aarch64" ]; then
        MICROMAMBA_URL="https://micro.mamba.pm/api/micromamba/linux-aarch64/latest"
    else
        echo "✗ Unsupported architecture: $ARCH"
        add_to_summary "✗ Architecture: UNSUPPORTED"
        exit 1
    fi
    
    # Download and extract
    if command -v curl >/dev/null 2>&1; then
        curl -Ls "$MICROMAMBA_URL" | tar -xvj bin/micromamba >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$MICROMAMBA_URL" | tar -xvj bin/micromamba >/dev/null 2>&1
    else
        echo "✗ Neither curl nor wget found. Please install one."
        add_to_summary "✗ Download tool: NOT FOUND"
        exit 1
    fi
    
    # Move to installation directory
    if [ -f "bin/micromamba" ]; then
        mv bin/micromamba "$MICROMAMBA_PATH"
        rmdir bin 2>/dev/null || true
        chmod +x "$MICROMAMBA_PATH"
        echo "✓ Micromamba installed successfully"
        MICROMAMBA_VERSION=$("$MICROMAMBA_PATH" --version 2>/dev/null | head -n1 || echo "installed")
        add_to_summary "✓ Micromamba: $MICROMAMBA_VERSION"
    else
        echo "✗ Failed to download micromamba"
        add_to_summary "✗ Micromamba: DOWNLOAD FAILED"
        exit 1
    fi
}

# Function to check if VADR environment exists
check_vadr_env() {
    echo ""
    echo "=== Checking VADR Environment ==="
    
    VADR_ENV_PATH="$INSTALL_DIR/envs/vadr_env"
    MICROMAMBA_PATH="$INSTALL_DIR/micromamba"
    
    if [ ! -f "$MICROMAMBA_PATH" ]; then
        echo "✗ Micromamba not found"
        add_to_summary "✗ VADR: MICROMAMBA MISSING"
        return 1
    fi
    
    if [ -d "$VADR_ENV_PATH" ]; then
        echo "✓ VADR environment exists at: $VADR_ENV_PATH"
        
        # Test VADR functionality
        if "$MICROMAMBA_PATH" run -p "$VADR_ENV_PATH" v-annotate.pl -h >/dev/null 2>&1; then
            VADR_VERSION=$("$MICROMAMBA_PATH" run -p "$VADR_ENV_PATH" v-annotate.pl -h 2>&1 | grep -o 'VADR [0-9.]*' | head -n1 || echo "installed")
            echo "✓ VADR is functional: $VADR_VERSION"
            add_to_summary "✓ VADR: $VADR_VERSION"
            
            # Check for models
            check_vadr_models
            return 0
        else
            echo "✗ VADR environment exists but VADR not functional"
            add_to_summary "✗ VADR: BROKEN ENVIRONMENT"
            
            if [ "$FORCE_REINSTALL" = true ]; then
                echo "Removing broken environment (--force-reinstall)..."
                rm -rf "$VADR_ENV_PATH"
            fi
            return 1
        fi
    else
        echo "✗ VADR environment not found at: $VADR_ENV_PATH"
        add_to_summary "✗ VADR: NOT INSTALLED"
        return 1
    fi
}

# Function to check VADR models
check_vadr_models() {
    VADR_ENV_PATH="$INSTALL_DIR/envs/vadr_env"
    MICROMAMBA_PATH="$INSTALL_DIR/micromamba"
    
    echo ""
    echo "VADR model information:"
    
    # Find VADR share directory
    VADR_SHARE=$(find "$VADR_ENV_PATH/share" -type d -name "vadr-*" 2>/dev/null | head -n1)
    
    if [ -n "$VADR_SHARE" ]; then
        echo "  VADR directory: $VADR_SHARE"
        
        # Check for viral model families
        for family in flaviviridae flavi coronaviridae corona caliciviridae sarscov2; do
            MODEL_DIR=$(find "$VADR_SHARE" -type d -name "*$family*" 2>/dev/null | head -n1)
            if [ -n "$MODEL_DIR" ]; then
                MODEL_COUNT=$(find "$MODEL_DIR" -name "*.cm" 2>/dev/null | wc -l)
                if [ "$MODEL_COUNT" -gt 0 ]; then
                    echo "  ✓ $family models: $MODEL_COUNT available"
                fi
            fi
        done
        
        # Count total models
        TOTAL_MODELS=$(find "$VADR_SHARE" -name "*.cm" 2>/dev/null | wc -l)
        if [ "$TOTAL_MODELS" -gt 0 ]; then
            echo "  Total models: $TOTAL_MODELS"
        else
            echo "  ⚠ No models found. Use download-vadr-models.sh to install models."
        fi
    else
        echo "  ⚠ VADR share directory not found"
    fi
}

# Function to install VADR
install_vadr() {
    echo ""
    echo "=== Installing VADR ==="
    
    if [ "$CHECK_ONLY" = true ]; then
        echo "Skipping installation (--check-only mode)"
        return 0
    fi
    
    VADR_ENV_PATH="$INSTALL_DIR/envs/vadr_env"
    MICROMAMBA_PATH="$INSTALL_DIR/micromamba"
    
    # Clean up existing environment if force reinstall
    if [ "$FORCE_REINSTALL" = true ] && [ -d "$VADR_ENV_PATH" ]; then
        echo "Removing existing VADR environment (--force-reinstall)..."
        rm -rf "$VADR_ENV_PATH"
    fi
    
    echo "Creating VADR environment..."
    echo "This may take several minutes for package resolution..."
    
    # Create environment with VADR
    if "$MICROMAMBA_PATH" create -p "$VADR_ENV_PATH" vadr -c bioconda -c conda-forge -y; then
        echo "✓ VADR environment created successfully"
        
        # Verify installation
        if "$MICROMAMBA_PATH" run -p "$VADR_ENV_PATH" v-annotate.pl -h >/dev/null 2>&1; then
            VADR_VERSION=$("$MICROMAMBA_PATH" run -p "$VADR_ENV_PATH" v-annotate.pl -h 2>&1 | grep -o 'VADR [0-9.]*' | head -n1 || echo "installed")
            echo "✓ VADR successfully installed: $VADR_VERSION"
            add_to_summary "✓ VADR: $VADR_VERSION (installed)"
        else
            echo "✗ VADR installation verification failed"
            add_to_summary "✗ VADR: VERIFICATION FAILED"
            return 1
        fi
    else
        echo "✗ Failed to create VADR environment"
        add_to_summary "✗ VADR: INSTALLATION FAILED"
        return 1
    fi
}

# Function to download common viral models
download_models() {
    echo ""
    echo "=== Downloading Viral Models ==="
    
    if [ "$CHECK_ONLY" = true ]; then
        echo "Skipping model download (--check-only mode)"
        return 0
    fi
    
    VADR_ENV_PATH="$INSTALL_DIR/envs/vadr_env"
    MICROMAMBA_PATH="$INSTALL_DIR/micromamba"
    
    echo "Downloading commonly used viral models..."
    
    # Download Flaviviridae models (for WNV, ZIKV, Dengue, etc.)
    echo "Downloading Flaviviridae models (WNV, ZIKV, Dengue)..."
    if "$MICROMAMBA_PATH" run -p "$VADR_ENV_PATH" download-vadr-models.sh flavi 2>&1 | grep -q "setup"; then
        echo "  ✓ Flaviviridae models installed"
    else
        echo "  ⚠ Failed to download Flaviviridae models"
    fi
    
    # Optionally download other common models
    echo ""
    echo "To download additional models, run:"
    echo "  $MICROMAMBA_PATH run -p $VADR_ENV_PATH download-vadr-models.sh <model_name>"
    echo ""
    echo "Available models: sarscov2, corona, calici, noro, flavi"
}

# Function to create wrapper scripts
create_wrappers() {
    echo ""
    echo "=== Creating Wrapper Scripts ==="
    
    if [ "$CHECK_ONLY" = true ]; then
        echo "Skipping wrapper creation (--check-only mode)"
        return 0
    fi
    
    WRAPPER_DIR="$INSTALL_DIR/vadr_wrappers"
    VADR_ENV_PATH="$INSTALL_DIR/envs/vadr_env"
    MICROMAMBA_PATH="$INSTALL_DIR/micromamba"
    
    mkdir -p "$WRAPPER_DIR"
    
    # Create v-annotate wrapper
    cat > "$WRAPPER_DIR/v-annotate.pl" << EOF
#!/bin/bash
# VADR v-annotate.pl wrapper script
# Automatically runs v-annotate.pl in the VADR environment
"$MICROMAMBA_PATH" run -p "$VADR_ENV_PATH" v-annotate.pl "\$@"
EOF
    
    chmod +x "$WRAPPER_DIR/v-annotate.pl"
    
    # Create v-build wrapper
    cat > "$WRAPPER_DIR/v-build.pl" << EOF
#!/bin/bash
# VADR v-build.pl wrapper script
# Automatically runs v-build.pl in the VADR environment
"$MICROMAMBA_PATH" run -p "$VADR_ENV_PATH" v-build.pl "\$@"
EOF
    
    chmod +x "$WRAPPER_DIR/v-build.pl"
    
    # Create download-models wrapper
    cat > "$WRAPPER_DIR/download-vadr-models.sh" << EOF
#!/bin/bash
# VADR model download wrapper script
# Downloads VADR models to the correct location
"$MICROMAMBA_PATH" run -p "$VADR_ENV_PATH" download-vadr-models.sh "\$@"
EOF
    
    chmod +x "$WRAPPER_DIR/download-vadr-models.sh"
    
    echo "✓ Wrapper scripts created in: $WRAPPER_DIR"
    echo "  - v-annotate.pl (main annotation tool)"
    echo "  - v-build.pl (model building tool)"
    echo "  - download-vadr-models.sh (model downloader)"
    
    add_to_summary "✓ Wrappers: $WRAPPER_DIR"
}

# Function to display usage instructions
show_usage_instructions() {
    echo ""
    echo "========================================="
    echo "VADR Installation Complete!"
    echo "========================================="
    echo ""
    echo "To use VADR:"
    echo ""
    echo "Method 1: Direct micromamba command"
    echo "  $INSTALL_DIR/micromamba run -p $INSTALL_DIR/envs/vadr_env v-annotate.pl --help"
    echo ""
    
    if [ -d "$INSTALL_DIR/vadr_wrappers" ]; then
        echo "Method 2: Wrapper scripts (simpler)"
        echo "  $INSTALL_DIR/vadr_wrappers/v-annotate.pl --help"
        echo "  export PATH=\"$INSTALL_DIR/vadr_wrappers:\$PATH\"  # Add to PATH for convenience"
        echo ""
    fi
    
    echo "Example: Annotate WNV genome (OP713603.1) using Flaviviridae models:"
    echo "  # Download genome"
    echo "  download_ncbi_genome OP713603.1"
    echo ""
    echo "  # Run VADR annotation"
    echo "  $INSTALL_DIR/vadr_wrappers/v-annotate.pl OP713603.1.fasta \\"
    echo "    --mdir $INSTALL_DIR/envs/vadr_env/share/vadr-*/vadr-models/vadr-models-flavi-* \\"
    echo "    --mkey flavi \\"
    echo "    --out OP713603.1_vadr"
    echo ""
    echo "  # Convert VADR output to snpEff format"
    echo "  python3 step2_add_to_snpeff.py OP713603.1 OP713603.1_vadr/*.gff --force"
}

# Function to display summary
display_summary() {
    echo ""
    echo "========================================="
    echo "Installation Summary"
    echo "========================================="
    echo -e "$INSTALL_SUMMARY"
    
    if [ "$CHECK_ONLY" != true ]; then
        show_usage_instructions
    fi
}

# Main execution
main() {
    echo "Script version: $SCRIPT_VERSION"
    echo ""
    
    check_directory_permissions
    install_micromamba
    
    if [ "$FORCE_REINSTALL" = true ]; then
        echo "Force reinstall requested, proceeding with installation..."
        install_vadr
        download_models
        create_wrappers
    elif check_vadr_env; then
        echo "VADR is already installed and functional"
        create_wrappers  # Update wrappers if needed
    else
        install_vadr
        download_models
        create_wrappers
    fi
    
    display_summary
}

# Run main function
main