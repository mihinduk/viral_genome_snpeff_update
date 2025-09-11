#!/bin/bash
# Setup script for snpEff with custom paths and dependency installation
# Version: 2.0.0 - Enhanced with full pipeline dependencies
# 
# Git versioning strategy:
#   - Tag releases: git tag -a v2.0.0 -m "Add pipeline dependencies"
#   - Push tags: git push origin v2.0.0
#   - View version: git describe --tags

set -e

SCRIPT_VERSION="2.0.0"

echo "========================================="
echo "snpEff Setup Script with Custom Paths"
echo "Version: $SCRIPT_VERSION"
echo "========================================="
echo ""

# Check if software path provided
if [ -z "$1" ]; then
    echo "Usage: $0 <software_directory_path> [--check-only]"
    echo ""
    echo "Example: $0 /ref/sahlab/software"
    echo ""
    echo "This script will install/check:"
    echo "  - Java 21: <software_dir>/jdk-21.0.5+11"
    echo "  - snpEff: <software_dir>/snpEff" 
    echo "  - Python packages: pandas (user install)"
    echo "  - System tools: curl/wget"
    echo "  - Pipeline configs: <software_dir>/snpeff_configs"
    echo ""
    echo "Options:"
    echo "  --check-only  Only check dependencies, don't install"
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
    
    # Check pandas
    if python3 -c "import pandas" >/dev/null 2>&1; then
        PANDAS_VERSION=$(python3 -c "import pandas; print(pandas.__version__)")
        echo "✓ pandas available: $PANDAS_VERSION"
        add_to_summary "✓ pandas: $PANDAS_VERSION"
    else
        echo "✗ pandas not available"
        add_to_summary "✗ pandas: NOT INSTALLED"
        
        if [ "$CHECK_ONLY" != "--check-only" ]; then
            echo "Installing pandas..."
            
            # Try different installation methods
            if command -v pip3 >/dev/null 2>&1; then
                echo "Using pip3..."
                pip3 install --user pandas
            elif command -v pip >/dev/null 2>&1; then
                echo "Using pip..."
                pip install --user pandas  
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
                echo "✓ pandas installed: $PANDAS_VERSION"
                add_to_summary "✓ pandas: INSTALLED ($PANDAS_VERSION)"
            fi
        fi
    fi
    
    # Check other useful packages
    echo ""
    echo "Optional Python packages:"
    
    for pkg in biopython requests numpy; do
        if python3 -c "import $pkg" >/dev/null 2>&1; then
            VERSION=$(python3 -c "import $pkg; print($pkg.__version__)" 2>/dev/null || echo "unknown")
            echo "  ✓ $pkg: $VERSION"
        else
            echo "  ○ $pkg: not installed (optional)"
        fi
    done
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
export PATH="\$JAVA_HOME/bin:\$PATH"

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
}

# Display configuration when sourced
if [ -n "\$PS1" ]; then
    echo "snpEff Pipeline loaded! (v\$SNPEFF_PIPELINE_VERSION)"
    echo "  Java: \$JAVA_HOME"
    echo "  snpEff: \$SNPEFF_HOME"
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
        echo "Version this installation in Git:"
        echo "  git add setup_snpeff_custom_paths.sh"
        echo "  git commit -m 'Update snpEff setup v$SCRIPT_VERSION'"
        echo "  git tag -a v$SCRIPT_VERSION -m 'Pipeline dependencies added'"
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
    create_update_config
    display_summary
}

# Run main function
main
