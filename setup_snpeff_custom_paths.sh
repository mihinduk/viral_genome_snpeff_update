#!/bin/bash
# Setup script for snpEff with custom paths and dependency installation
# Version: 2.0.0 - Enhanced with full pipeline dependencies
# 
# Git versioning strategy:
#   - Tag releases: git tag -a v2.0.0 -m "Add pipeline dependencies"
#   - Push tags: git push origin v2.0.0
#   - View version: git describe --tags

set -e

SCRIPT_VERSION="2.2.0"

echo "========================================="
echo "snpEff Setup Script with Custom Paths"
echo "Version: $SCRIPT_VERSION"
echo "========================================="
echo ""

# Check if software path provided
if [ -z "$1" ]; then
    echo "Usage: $0 <software_directory_path> [--check-only]"
    echo "   or: SCRATCH_DIR=<scratch_path> $0 <software_directory_path> [--check-only]"
    echo ""
    echo "Examples:"
    echo "  $0 /ref/sahlab/software"
    echo "  SCRATCH_DIR=/scratch/sahlab/kathie $0 /ref/sahlab/software"
    echo ""
    echo "This script will install/check:"
    echo "  - Java 21: <software_dir>/jdk-21.0.5+11"
    echo "  - snpEff: <software_dir>/snpEff" 
    echo "  - Python packages: pandas, biopython (scratch space install)"
    echo "  - VADR: viral annotation via bioconda"
    echo "  - System tools: curl/wget"
    echo "  - Pipeline configs: <software_dir>/snpeff_configs"
    echo ""
    echo "Options:"
    echo "  --check-only     Only check dependencies, don't install"
    echo "  SCRATCH_DIR=<path>  Specify scratch directory for Python packages"
    echo "                     (will prompt if not specified)"
    exit 1
fi

SOFTWARE_DIR="$1"
CHECK_ONLY="${2:-}"

echo "Software directory: $SOFTWARE_DIR"
[ "$CHECK_ONLY" = "--check-only" ] && echo "Mode: Check only (no installation)"

# Track installation status
INSTALL_SUMMARY=""

# Function to add to summary
add_to_summary() {
    INSTALL_SUMMARY="${INSTALL_SUMMARY}$1\n"
}

# Function to check and install system packages
check_system_deps() {
    echo ""
    echo "=== Checking System Dependencies ==="
    
    # Check curl/wget
    if command -v curl >/dev/null 2>&1; then
        echo "✓ curl is available"
        DOWNLOAD_CMD="curl -L -o"
        add_to_summary "✓ curl: available"
    elif command -v wget >/dev/null 2>&1; then
        echo "✓ wget is available"  
        DOWNLOAD_CMD="wget -O"
        add_to_summary "✓ wget: available"
    else
        echo "✗ Neither curl nor wget found"
        add_to_summary "✗ curl/wget: MISSING"
        if [ "$CHECK_ONLY" != "--check-only" ]; then
            echo "Please install curl or wget:"
            echo "  sudo yum install curl  # RHEL/CentOS"
            echo "  sudo apt-get install curl  # Ubuntu/Debian"
            exit 1
        fi
    fi
    
    # Check Python
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
        echo "✓ Python 3 available: $PYTHON_VERSION"
        add_to_summary "✓ Python: $PYTHON_VERSION"
    else
        echo "✗ Python 3 not found"
        add_to_summary "✗ Python 3: MISSING"
        if [ "$CHECK_ONLY" != "--check-only" ]; then
            echo "Please install Python 3:"
            echo "  sudo yum install python3  # RHEL/CentOS"
            echo "  sudo apt-get install python3  # Ubuntu/Debian"
            exit 1
        fi
    fi
    
    # Check unzip
    if command -v unzip >/dev/null 2>&1; then
        echo "✓ unzip is available"
        add_to_summary "✓ unzip: available"
    else
        echo "⚠ unzip not found (needed for snpEff installation)"
        add_to_summary "⚠ unzip: MISSING"
    fi
}

# Function to check/install Java 21
check_install_java21() {
    echo ""
    echo "=== Java 21 ==="
    
    JAVA_DIR="$SOFTWARE_DIR/jdk-21.0.5+11"
    
    if [ -f "$JAVA_DIR/bin/java" ]; then
        JAVA_VERSION=$("$JAVA_DIR/bin/java" -version 2>&1 | head -1 | awk -F'"' '{print $2}')
        echo "✓ Java already installed: $JAVA_VERSION at $JAVA_DIR"
        add_to_summary "✓ Java 21: $JAVA_VERSION"
        return 0
    fi
    
    echo "✗ Java 21 not found at $JAVA_DIR"
    add_to_summary "✗ Java 21: NOT INSTALLED"
    
    if [ "$CHECK_ONLY" = "--check-only" ]; then
        return 1
    fi
    
    echo "Installing Java 21..."
    mkdir -p "$SOFTWARE_DIR"
    
    if [ "$DOWNLOAD_CMD" = "curl -L -o" ]; then
        $DOWNLOAD_CMD "$SOFTWARE_DIR/openjdk21.tar.gz" "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_x64_linux_hotspot_21.0.5_11.tar.gz"
    else
        $DOWNLOAD_CMD "$SOFTWARE_DIR/openjdk21.tar.gz" "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_x64_linux_hotspot_21.0.5_11.tar.gz"
    fi
    
    echo "Extracting Java 21..."
    tar -xzf "$SOFTWARE_DIR/openjdk21.tar.gz" -C "$SOFTWARE_DIR"
    rm "$SOFTWARE_DIR/openjdk21.tar.gz"
    
    echo "✓ Java 21 installed to $JAVA_DIR"
    add_to_summary "✓ Java 21: INSTALLED"
}

# Function to check/install snpEff
check_install_snpeff() {
    echo ""
    echo "=== snpEff ==="
    
    SNPEFF_DIR="$SOFTWARE_DIR/snpEff"
    
    if [ -f "$SNPEFF_DIR/snpEff.jar" ]; then
        # Try to get version
        if [ -f "$JAVA_DIR/bin/java" ]; then
            SNPEFF_VERSION=$("$JAVA_DIR/bin/java" -jar "$SNPEFF_DIR/snpEff.jar" -version 2>&1 | head -1 || echo "unknown")
            echo "✓ snpEff already installed at $SNPEFF_DIR"
            echo "  Version: $SNPEFF_VERSION"
            add_to_summary "✓ snpEff: $SNPEFF_VERSION"
        else
            echo "✓ snpEff found at $SNPEFF_DIR (version check requires Java)"
            add_to_summary "✓ snpEff: found"
        fi
        return 0
    fi
    
    echo "✗ snpEff not found at $SNPEFF_DIR"
    add_to_summary "✗ snpEff: NOT INSTALLED"
    
    if [ "$CHECK_ONLY" = "--check-only" ]; then
        return 1
    fi
    
    echo "Installing snpEff..."
    
    if [ "$DOWNLOAD_CMD" = "curl -L -o" ]; then
        $DOWNLOAD_CMD "$SOFTWARE_DIR/snpEff_latest_core.zip" "https://snpeff.blob.core.windows.net/versions/snpEff_latest_core.zip"
    else
        $DOWNLOAD_CMD "$SOFTWARE_DIR/snpEff_latest_core.zip" "https://snpeff.blob.core.windows.net/versions/snpEff_latest_core.zip"
    fi
    
    echo "Extracting snpEff..."
    unzip -q "$SOFTWARE_DIR/snpEff_latest_core.zip" -d "$SOFTWARE_DIR"
    rm "$SOFTWARE_DIR/snpEff_latest_core.zip"
    
    echo "✓ snpEff installed to $SNPEFF_DIR"
    add_to_summary "✓ snpEff: INSTALLED"
}

# Function to check/install Python packages
check_install_python_deps() {
    echo ""
    echo "=== Python Dependencies ==="
    
    # Setup PIP cache and install location in scratch space to avoid home directory quota issues
    if [ -n "$SCRATCH_DIR" ]; then
        # Use user-provided scratch directory
        export PIP_CACHE_DIR="$SCRATCH_DIR/.cache/pip"
        export PIP_USER_DIR="$SCRATCH_DIR/.local"
    elif [ -n "$USER" ]; then
        # Fallback: ask user for scratch directory
        echo ""
        echo "⚠ Scratch directory not specified. Please provide your scratch space path."
        echo "Common examples:"
        echo "  - /scratch/\$USER"
        echo "  - /scratch/sahlab/\$USER"
        echo "  - /tmp/\$USER"
        read -p "Enter your scratch directory path: " SCRATCH_INPUT
        
        if [ -n "$SCRATCH_INPUT" ]; then
            export PIP_CACHE_DIR="$SCRATCH_INPUT/.cache/pip"
            export PIP_USER_DIR="$SCRATCH_INPUT/.local"
        else
            echo "⚠ No scratch directory provided, using home directory (may hit quota limits)"
            export PIP_USER_DIR="$HOME/.local"
            export PIP_CACHE_DIR="$HOME/.cache/pip"
        fi
    else
        echo "⚠ Warning: \$USER not set, using default PIP locations"
        export PIP_USER_DIR="$HOME/.local"
        export PIP_CACHE_DIR="$HOME/.cache/pip"
    fi
    
    export PYTHONUSERBASE="$PIP_USER_DIR"
    export PATH="$PIP_USER_DIR/bin:$PATH"
    
    echo "Setting PIP cache directory: $PIP_CACHE_DIR"
    echo "Setting PIP install directory: $PIP_USER_DIR"
    
    if [ "$CHECK_ONLY" != "--check-only" ]; then
        mkdir -p "$PIP_CACHE_DIR" "$PIP_USER_DIR" 2>/dev/null || {
            echo "⚠ Warning: Could not create PIP directories in scratch space"
            echo "  This may cause slower installs but won't prevent installation"
        }
    fi
    
    # Check pandas (check both standard location and scratch space)
    PANDAS_FOUND=false
    if python3 -c "import pandas" >/dev/null 2>&1; then
        PANDAS_VERSION=$(python3 -c "import pandas; print(pandas.__version__)")
        PANDAS_LOCATION=$(python3 -c "import pandas; print(pandas.__file__)")
        echo "✓ pandas available: $PANDAS_VERSION"
        echo "  Location: $PANDAS_LOCATION"
        add_to_summary "✓ pandas: $PANDAS_VERSION"
        PANDAS_FOUND=true
    fi
    
    if [ "$PANDAS_FOUND" = false ]; then
        echo "✗ pandas not available"
        add_to_summary "✗ pandas: NOT INSTALLED"
        
        if [ "$CHECK_ONLY" != "--check-only" ]; then
            echo "Installing pandas to scratch space..."
            echo "Target directory: $PIP_USER_DIR"
            
            # Try different installation methods
            if command -v pip3 >/dev/null 2>&1; then
                echo "Using pip3 with scratch space installation..."
                env PYTHONUSERBASE="$PIP_USER_DIR" PIP_CACHE_DIR="$PIP_CACHE_DIR" pip3 install --user pandas
            elif command -v pip >/dev/null 2>&1; then
                echo "Using pip with scratch space installation..."
                env PYTHONUSERBASE="$PIP_USER_DIR" PIP_CACHE_DIR="$PIP_CACHE_DIR" pip install --user pandas  
            elif command -v conda >/dev/null 2>&1; then
                echo "Using conda..."
                conda install pandas -y
            else
                echo "⚠ Warning: No package manager found (pip, conda)"
                echo "Please install pandas manually:"
                echo "  pip3 install --user pandas"
                return 1
            fi
            
            # Verify installation
            if python3 -c "import pandas" >/dev/null 2>&1; then
                PANDAS_VERSION=$(python3 -c "import pandas; print(pandas.__version__)")
                PANDAS_LOCATION=$(python3 -c "import pandas; print(pandas.__file__)")
                echo "✓ pandas successfully installed: $PANDAS_VERSION"
                echo "  Installed to: $PANDAS_LOCATION"
                # Update summary to replace the NOT INSTALLED entry
                INSTALL_SUMMARY=$(echo -e "$INSTALL_SUMMARY" | sed 's/✗ pandas: NOT INSTALLED/✓ pandas: INSTALLED ('"$PANDAS_VERSION"')/')
            else
                echo "✗ pandas installation failed"
            fi
        fi
    fi
    
    # Check other useful packages
    echo ""
    echo "Additional Python packages:"
    
    for pkg in biopython requests numpy; do
        if python3 -c "import $pkg" >/dev/null 2>&1; then
            VERSION=$(python3 -c "import $pkg; print($pkg.__version__)" 2>/dev/null || echo "unknown")
            echo "  ✓ $pkg: $VERSION"
        else
            echo "  ○ $pkg: not installed (recommended for viral genomics)"
            if [ "$CHECK_ONLY" != "--check-only" ] && [ "$pkg" = "biopython" ]; then
                echo "    Installing biopython..."
                if command -v pip3 >/dev/null 2>&1; then
                    env PYTHONUSERBASE="$PIP_USER_DIR" PIP_CACHE_DIR="$PIP_CACHE_DIR" pip3 install --user biopython
                elif command -v conda >/dev/null 2>&1; then
                    conda install biopython -y
                fi
            fi
        fi
    done
}

# Function to check/install VADR
check_install_vadr() {
    echo ""
    echo "=== VADR (Viral Annotation and Discovery Repository) ==="
    
    # Check if VADR is available
    if command -v v-annotate.pl >/dev/null 2>&1; then
        VADR_VERSION=$(v-annotate.pl -h 2>&1 | grep -o 'VADR [0-9.]*' | head -n1 || echo "unknown")
        VADR_PATH=$(which v-annotate.pl)
        echo "✓ VADR available: $VADR_VERSION"
        echo "  Location: $VADR_PATH"
        add_to_summary "✓ VADR: $VADR_VERSION"
    else
        echo "✗ VADR not found"
        add_to_summary "✗ VADR: NOT INSTALLED"
        
        if [ "$CHECK_ONLY" != "--check-only" ]; then
            echo "Installing VADR via conda (bioconda channel)..."
            
            if command -v conda >/dev/null 2>&1; then
                echo "Adding bioconda channel..."
                conda config --add channels bioconda
                conda config --add channels conda-forge
                
                echo "Installing VADR (this may take several minutes)..."
                conda install -c bioconda vadr=1.6.4 -y
                
                # Verify installation
                if command -v v-annotate.pl >/dev/null 2>&1; then
                    VADR_VERSION=$(v-annotate.pl -h 2>&1 | grep -o 'VADR [0-9.]*' | head -n1 || echo "installed")
                    echo "✓ VADR successfully installed: $VADR_VERSION"
                    echo "✓ Available commands: v-annotate.pl, v-build.pl"
                    
                    # Update summary
                    INSTALL_SUMMARY=$(echo -e "$INSTALL_SUMMARY" | sed 's/✗ VADR: NOT INSTALLED/✓ VADR: '"$VADR_VERSION"'/')
                else
                    echo "✗ VADR installation failed"
                    echo "  You can try manual installation:"
                    echo "  conda install -c bioconda vadr"
                fi
            else
                echo "⚠ conda not available. VADR requires conda for installation."
                echo "Please install conda/miniconda first, then run:"
                echo "  conda install -c bioconda vadr"
                return 1
            fi
        fi
    fi
    
    # Check VADR model directories
    if command -v v-annotate.pl >/dev/null 2>&1; then
        echo ""
        echo "VADR model information:"
        
        # Try to find VADR installation directory
        VADR_DIR=$(dirname $(which v-annotate.pl))/../share/vadr 2>/dev/null || ""
        
        if [ -d "$VADR_DIR" ]; then
            echo "  VADR directory: $VADR_DIR"
            
            # Check for viral model families
            for family in flaviviridae coronaviridae; do
                if [ -d "$VADR_DIR/vadr-models-$family" ]; then
                    MODEL_COUNT=$(ls "$VADR_DIR/vadr-models-$family"/*.cm 2>/dev/null | wc -l)
                    echo "  ✓ $family models: $MODEL_COUNT available"
                else
                    echo "  ○ $family models: not found"
                fi
            done
        else
            echo "  Model directory not found at expected location"
            echo "  Models should be automatically included with bioconda installation"
        fi
    fi
}

# Function to create/update pipeline configuration
create_update_config() {
    echo ""
    echo "=== Pipeline Configuration ==="
    
    CONFIG_DIR="$SOFTWARE_DIR/snpeff_configs"
    JAVA_DIR="$SOFTWARE_DIR/jdk-21.0.5+11"
    SNPEFF_DIR="$SOFTWARE_DIR/snpEff"
    
    if [ "$CHECK_ONLY" = "--check-only" ]; then
        if [ -f "$CONFIG_DIR/snpeff_env.sh" ]; then
            echo "✓ Configuration exists: $CONFIG_DIR/snpeff_env.sh"
            add_to_summary "✓ Config: exists"
        else
            echo "✗ Configuration not found"
            add_to_summary "✗ Config: NOT FOUND"
        fi
        return 0
    fi
    
    mkdir -p "$CONFIG_DIR"
    
    # Create versioned configuration with metadata
    cat > "$CONFIG_DIR/snpeff_env.sh" << CONFIG_EOF
#!/bin/bash
# snpEff Pipeline Configuration
# Version: $SCRIPT_VERSION
# Generated: $(date)
# Git commit: $(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

export SNPEFF_PIPELINE_VERSION="$SCRIPT_VERSION"
export JAVA_HOME="$JAVA_DIR"
export SNPEFF_HOME="$SNPEFF_DIR"

# Python package management in scratch space
# Note: Set SCRATCH_DIR environment variable or script will prompt for scratch path
export PIP_CACHE_DIR="\${SCRATCH_DIR:-/scratch/\$USER}/.cache/pip"
export PIP_USER_DIR="\${SCRATCH_DIR:-/scratch/\$USER}/.local"
export PYTHONUSERBASE="\$PIP_USER_DIR"

# Update PATH to include both Java and Python packages
export PATH="\$JAVA_HOME/bin:\$PIP_USER_DIR/bin:\$PATH"

# Core functions
snpeff() {
    "\$JAVA_HOME/bin/java" -Xmx4g -jar "\$SNPEFF_HOME/snpEff.jar" "\$@"
}

snpsift() {
    "\$JAVA_HOME/bin/java" -Xmx4g -jar "\$SNPEFF_HOME/SnpSift.jar" "\$@"
}

# NCBI download function
download_ncbi_genome() {
    local accession="\$1"
    if [ -z "\$accession" ]; then
        echo "Usage: download_ncbi_genome <NCBI_ACCESSION>"
        return 1
    fi
    
    echo "Downloading \$accession from NCBI..."
    
    # Download FASTA
    curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=\$accession&rettype=fasta&retmode=text" > "\$accession.fasta"
    
    # Download GenBank
    curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=\$accession&rettype=gb&retmode=text" > "\$accession.gb"
    
    # Download GFF3
    curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=\$accession&rettype=gff3&retmode=text" > "\$accession.gff3"
    
    echo "Downloaded: \$accession.fasta, \$accession.gb, \$accession.gff3"
}

# Display version
snpeff_pipeline_version() {
    echo "snpEff Pipeline Version: \$SNPEFF_PIPELINE_VERSION"
    echo "Java: \$JAVA_HOME"
    echo "snpEff: \$SNPEFF_HOME"
    echo "Python packages: \$PYTHONUSERBASE"
}

# Display configuration when sourced
if [ -n "\$PS1" ]; then
    echo "snpEff Pipeline loaded! (v\$SNPEFF_PIPELINE_VERSION)"
    echo "  Java: \$JAVA_HOME"
    echo "  snpEff: \$SNPEFF_HOME"
    echo "  Python: \$PYTHONUSERBASE"
    echo ""
    echo "Functions: snpeff, snpsift, download_ncbi_genome, snpeff_pipeline_version"
fi
CONFIG_EOF
    
    chmod +x "$CONFIG_DIR/snpeff_env.sh"
    
    # Create/update current symlink
    ln -sf "$CONFIG_DIR/snpeff_env.sh" "$CONFIG_DIR/snpeff_current.sh"
    
    echo "✓ Configuration created/updated"
    add_to_summary "✓ Config: CREATED"
}

# Function to display summary
display_summary() {
    echo ""
    echo "========================================="
    echo "Installation Summary"
    echo "========================================="
    echo -e "$INSTALL_SUMMARY"
    
    if [ "$CHECK_ONLY" != "--check-only" ]; then
        echo ""
        echo "To use the pipeline:"
        echo "  source $SOFTWARE_DIR/snpeff_configs/snpeff_current.sh"
        echo ""
        echo "Note: Python packages are installed in scratch space (/scratch/\$USER/.local/)"
        echo "This avoids home directory quota issues on HPC systems."
        echo ""
        echo "Version this installation in Git:"
        echo "  git add setup_snpeff_custom_paths.sh"
        echo "  git commit -m 'Update snpEff setup v$SCRIPT_VERSION'"
        echo "  git tag -a v$SCRIPT_VERSION -m 'Scratch space support for Python packages'"
        echo "  git push origin main --tags"
    fi
}

# Main execution
main() {
    echo "Script version: $SCRIPT_VERSION"
    
    # Check permissions
    if [ "$CHECK_ONLY" != "--check-only" ]; then
        if [ ! -w "$SOFTWARE_DIR" ] && [ ! -d "$SOFTWARE_DIR" ]; then
            echo "Creating software directory: $SOFTWARE_DIR"
            mkdir -p "$SOFTWARE_DIR" 2>/dev/null || {
                echo "Cannot create $SOFTWARE_DIR. You may need sudo:"
                echo "  sudo mkdir -p $SOFTWARE_DIR"
                echo "  sudo chown $USER:$(id -gn) $SOFTWARE_DIR"
                exit 1
            }
        fi
    fi
    
    check_system_deps
    check_install_java21
    check_install_snpeff  
    check_install_python_deps
    check_install_vadr
    create_update_config
    display_summary
}

# Run main function
main
