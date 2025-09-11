#!/bin/bash
# Setup script for snpEff with user-provided custom paths
# Requires Java 21+ for snpEff 5.2e+
# Supports multiple version configurations

set -e

echo "========================================="
echo "snpEff Setup Script with Custom Paths"
echo "========================================="
echo ""
echo "CRITICAL: Java Requirements"
echo "- Minimum: Java 11 for older snpEff versions"
echo "- Current: Java 21 for snpEff 5.2e+"
echo ""

# Default configuration directory (can be overridden by environment variable)
DEFAULT_CONFIG_BASE="${SNPEFF_CONFIG_BASE:-/ref/sahlab/software}"

# Function to check disk space
check_disk_space() {
    local path="$1"
    local required_mb="$2"
    
    # Get available space
    local available_kb=$(df "$path" 2>/dev/null | tail -1 | awk '{print $4}')
    
    if [ -z "$available_kb" ]; then
        echo "⚠ Warning: Cannot determine available disk space for $path"
        echo "  If you have admin privileges, ensure adequate space is available."
        return 0
    fi
    
    local available_mb=$((available_kb / 1024))
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        echo "⚠ WARNING: Low disk space detected"
        echo "  Path: $path"
        echo "  Available: ${available_mb}MB"
        echo "  Recommended: ${required_mb}MB"
        echo ""
        echo "  If you have admin privileges:"
        echo "    - Consider cleaning up old files: sudo du -sh $path/* | sort -h"
        echo "    - Or expand the filesystem if possible"
        echo ""
        read -p "Continue anyway? (y/n): " continue_anyway
        if [ "$continue_anyway" != "y" ]; then
            return 1
        fi
    else
        echo "✓ Sufficient disk space (${available_mb}MB available)"
    fi
    
    return 0
}

# Function to check write permissions
check_write_permission() {
    local path="$1"
    local test_file="${path}/.snpeff_test_$$"
    
    # Try to create a test file
    if touch "$test_file" 2>/dev/null; then
        rm -f "$test_file"
        echo "✓ Write permission verified for $path"
        return 0
    else
        echo "⚠ WARNING: No write permission for $path"
        echo ""
        echo "  If you have admin privileges, try:"
        echo "    sudo chown $USER:$USER $path"
        echo "    OR"
        echo "    sudo chmod 755 $path"
        echo ""
        echo "  To create the directory with proper permissions:"
        echo "    sudo mkdir -p $path"
        echo "    sudo chown $USER:$(id -gn) $path"
        echo ""
        return 1
    fi
}

# Function to validate Java installation
validate_java() {
    local java_path="$1"
    
    if [ ! -d "$java_path" ]; then
        echo "✗ Error: Directory does not exist: $java_path"
        echo ""
        echo "  If you need to install Java 21 with admin privileges:"
        echo "    sudo mkdir -p $(dirname $java_path)"
        echo "    sudo wget -O /tmp/openjdk21.tar.gz https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.5%2B11/OpenJDK21U-jdk_x64_linux_hotspot_21.0.5_11.tar.gz"
        echo "    sudo tar -xzf /tmp/openjdk21.tar.gz -C $(dirname $java_path)"
        echo "    sudo mv $(dirname $java_path)/jdk-21.0.5+11 $java_path"
        return 1
    fi
    
    if [ ! -f "$java_path/bin/java" ]; then
        echo "✗ Error: Java executable not found at $java_path/bin/java"
        echo "  Please ensure you provide the Java home directory, not the bin directory."
        return 1
    fi
    
    # Check if we can execute the Java binary
    if [ ! -x "$java_path/bin/java" ]; then
        echo "✗ Error: Java binary is not executable: $java_path/bin/java"
        echo ""
        echo "  Fix with admin privileges:"
        echo "    sudo chmod +x $java_path/bin/java"
        return 1
    fi
    
    # Check Java version
    local java_version=$("$java_path/bin/java" -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
    local major_version=$(echo $java_version | cut -d. -f1)
    
    # For versions like 1.8.x, the major version is the second number
    if [ "$major_version" = "1" ]; then
        major_version=$(echo $java_version | cut -d. -f2)
    fi
    
    echo "Found Java version: $java_version (Major: $major_version)"
    
    if [ "$major_version" -lt 11 ]; then
        echo "✗ Error: Java version is too old. snpEff requires Java 11 minimum."
        echo "  Current version: $java_version"
        echo "  Minimum required: Java 11"
        echo "  Recommended: Java 21+ for snpEff 5.2e+"
        return 1
    elif [ "$major_version" -lt 21 ]; then
        echo "⚠ Warning: Java version is less than 21."
        echo "  Current version: $java_version"
        echo "  This is sufficient for older snpEff versions but snpEff 5.2e+ requires Java 21"
        read -p "Do you want to continue with Java $major_version? (y/n): " continue_anyway
        if [ "$continue_anyway" != "y" ]; then
            return 1
        fi
    else
        echo "✓ Java version is compatible (21+) - optimal for latest snpEff"
    fi
    
    return 0
}

# Function to validate snpEff installation
validate_snpeff() {
    local snpeff_path="$1"
    
    if [ ! -d "$snpeff_path" ]; then
        echo "✗ Error: Directory does not exist: $snpeff_path"
        echo ""
        echo "  To install snpEff with admin privileges:"
        echo "    sudo mkdir -p $snpeff_path"
        echo "    sudo wget -O /tmp/snpEff_latest_core.zip https://snpeff.blob.core.windows.net/versions/snpEff_latest_core.zip"
        echo "    sudo unzip /tmp/snpEff_latest_core.zip -d $(dirname $snpeff_path)"
        echo "    sudo chown -R $USER:$(id -gn) $snpeff_path"
        return 1
    fi
    
    if [ ! -f "$snpeff_path/snpEff.jar" ]; then
        echo "✗ Error: snpEff.jar not found at $snpeff_path/snpEff.jar"
        echo "  Please ensure you provide the snpEff directory containing snpEff.jar"
        return 1
    fi
    
    # Check if we can read the jar file
    if [ ! -r "$snpeff_path/snpEff.jar" ]; then
        echo "✗ Error: Cannot read snpEff.jar - permission denied"
        echo ""
        echo "  Fix with admin privileges:"
        echo "    sudo chmod +r $snpeff_path/snpEff.jar"
        return 1
    fi
    
    echo "✓ Found snpEff.jar at $snpeff_path"
    
    # Check for SnpSift.jar
    if [ -f "$snpeff_path/SnpSift.jar" ]; then
        echo "✓ Found SnpSift.jar"
    else
        echo "⚠ Warning: SnpSift.jar not found at $snpeff_path"
        echo "  The snpSift wrapper will not work without it."
    fi
    
    return 0
}

# Function to list existing configurations
list_configurations() {
    local config_dir="$1"
    
    if [ -d "$config_dir" ]; then
        echo ""
        echo "Existing snpEff configurations:"
        echo "--------------------------------"
        
        # Check for current symlink
        if [ -L "${config_dir}/snpeff_current.sh" ]; then
            local current=$(readlink "${config_dir}/snpeff_current.sh" | xargs basename)
            echo "Current: $current"
        fi
        
        # List all configuration files
        for config in "${config_dir}"/snpeff_*_env.sh; do
            if [ -f "$config" ]; then
                local basename=$(basename "$config")
                local name=${basename%_env.sh}
                name=${name#snpeff_}
                
                # Extract version info from file
                local java_info=$(grep "^# Java:" "$config" 2>/dev/null | cut -d: -f2-)
                local snpeff_info=$(grep "^# snpEff:" "$config" 2>/dev/null | cut -d: -f2-)
                
                echo "  - $name"
                [ -n "$java_info" ] && echo "      Java:$java_info"
                [ -n "$snpeff_info" ] && echo "      snpEff:$snpeff_info"
            fi
        done
        echo ""
    fi
}

# Get configuration name/version
echo "Enter a name/version for this configuration (e.g., 5.2f, latest, test)"
echo "This allows multiple snpEff versions to coexist"
read -p "Configuration name [default]: " CONFIG_VERSION
CONFIG_VERSION="${CONFIG_VERSION:-default}"

# Sanitize configuration name (remove spaces and special characters)
CONFIG_VERSION=$(echo "$CONFIG_VERSION" | sed 's/[^a-zA-Z0-9._-]/_/g')

echo ""
echo "Configuration will be named: snpeff_${CONFIG_VERSION}"

# Get Java path from user (or use command line argument)
if [ -n "$1" ]; then
    JAVA_PATH="$1"
    echo "Using Java path from command line: $JAVA_PATH"
else
    echo ""
    echo "Please provide the path to your Java installation."
    echo "This should be the directory containing 'bin/java'"
    echo "Examples:"
    echo "  - /usr/lib/jvm/java-21-openjdk"
    echo "  - /apps/java/jdk-21.0.1"
    echo "  - /ref/sahlab/software/jdk-21.0.5+11"
    echo "  - \$HOME/.local/java21"
    echo ""
    read -p "Enter Java installation path: " JAVA_PATH
fi

# Remove trailing slash if present
JAVA_PATH="${JAVA_PATH%/}"

# Expand ~ to home directory if used
JAVA_PATH="${JAVA_PATH/#\~/$HOME}"

# Validate Java installation
echo ""
echo "Validating Java installation..."
if ! validate_java "$JAVA_PATH"; then
    echo ""
    echo "✗ Java validation failed."
    exit 1
fi

# Get snpEff path from user (or use command line argument)
if [ -n "$2" ]; then
    SNPEFF_PATH="$2"
    echo "Using snpEff path from command line: $SNPEFF_PATH"
else
    echo ""
    echo "Please provide the path to your snpEff installation."
    echo "This should be the directory containing 'snpEff.jar'"
    echo "Examples:"
    echo "  - /apps/snpEff"
    echo "  - /home/mihindu/software/snpEff"
    echo "  - \$HOME/.local/snpEff"
    echo ""
    read -p "Enter snpEff installation path: " SNPEFF_PATH
fi

# Remove trailing slash if present
SNPEFF_PATH="${SNPEFF_PATH%/}"

# Expand ~ to home directory if used
SNPEFF_PATH="${SNPEFF_PATH/#\~/$HOME}"

# Validate snpEff installation
echo ""
echo "Validating snpEff installation..."
if ! validate_snpeff "$SNPEFF_PATH"; then
    echo ""
    echo "✗ snpEff validation failed."
    exit 1
fi

# Get memory allocation
echo ""
read -p "Enter maximum memory for snpEff (e.g., 4g, 8g, 16g) [default: 4g]: " MAX_MEM
MAX_MEM="${MAX_MEM:-4g}"
echo "Will use -Xmx${MAX_MEM} for Java heap size"

# Test snpEff with the provided Java
echo ""
echo "Testing snpEff with provided Java..."
if "$JAVA_PATH/bin/java" -jar "$SNPEFF_PATH/snpEff.jar" -version 2>/dev/null; then
    echo "✓ snpEff is working correctly with the provided Java!"
    
    # Try to extract actual snpEff version
    DETECTED_VERSION=$("$JAVA_PATH/bin/java" -jar "$SNPEFF_PATH/snpEff.jar" -version 2>&1 | grep -oP 'SnpEff\s+\K[0-9.]+[a-z]*' | head -1)
    if [ -n "$DETECTED_VERSION" ]; then
        echo "snpEff version detected: $DETECTED_VERSION"
        
        # Ask if user wants to use detected version for naming
        if [ "$CONFIG_VERSION" = "default" ]; then
            read -p "Use detected version ($DETECTED_VERSION) for configuration name? (y/n): " use_detected
            if [ "$use_detected" = "y" ]; then
                CONFIG_VERSION="$DETECTED_VERSION"
                echo "Configuration will be named: snpeff_${CONFIG_VERSION}"
            fi
        fi
    fi
    
    # Check Java compatibility with snpEff version
    if [[ "$DETECTED_VERSION" > "5.2d" ]]; then
        JAVA_VERSION=$("$JAVA_PATH/bin/java" -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
        MAJOR_VERSION=$(echo $JAVA_VERSION | cut -d. -f1)
        if [ "$MAJOR_VERSION" = "1" ]; then
            MAJOR_VERSION=$(echo $JAVA_VERSION | cut -d. -f2)
        fi
        
        if [ "$MAJOR_VERSION" -lt 21 ]; then
            echo "⚠ WARNING: snpEff $DETECTED_VERSION requires Java 21+"
            echo "  You are using Java $MAJOR_VERSION which may cause issues"
        fi
    fi
else
    echo "✗ Failed to run snpEff with the provided Java."
    echo "  This could be due to:"
    echo "  - Incompatible Java version"
    echo "  - Corrupted snpEff installation"
    echo "  - Missing dependencies"
    exit 1
fi

# Determine configuration directory
echo ""
echo "Determining configuration location..."
echo "Base directory (set SNPEFF_CONFIG_BASE to override): $DEFAULT_CONFIG_BASE"

CONFIG_DIR="${DEFAULT_CONFIG_BASE}/snpeff_configs"

# Try to create the configuration directory
if [ ! -d "$CONFIG_DIR" ]; then
    echo "Creating configuration directory: $CONFIG_DIR"
    if ! mkdir -p "$CONFIG_DIR" 2>/dev/null; then
        echo "⚠ Cannot create $CONFIG_DIR without admin privileges"
        echo ""
        echo "  To create with admin privileges:"
        echo "    sudo mkdir -p $CONFIG_DIR"
        echo "    sudo chown $USER:$(id -gn) $CONFIG_DIR"
        echo ""
        echo "Falling back to home directory..."
        CONFIG_DIR="${HOME}/.snpeff_configs"
        mkdir -p "$CONFIG_DIR" 2>/dev/null || {
            echo "✗ ERROR: Cannot create configuration directory"
            exit 1
        }
    fi
fi

# Show existing configurations
list_configurations "$CONFIG_DIR"

# Set configuration file name with version
CONFIG_NAME="snpeff_${CONFIG_VERSION}"
CONFIG_FILE="${CONFIG_DIR}/${CONFIG_NAME}_env.sh"

# Check for existing configuration
if [ -f "$CONFIG_FILE" ]; then
    echo "⚠ Configuration already exists: $CONFIG_FILE"
    read -p "Overwrite existing configuration? (y/n): " overwrite
    if [ "$overwrite" != "y" ]; then
        echo "Keeping existing configuration."
        echo "To use it: source $CONFIG_FILE"
        exit 0
    fi
fi

# Check permissions and space
echo ""
if ! check_write_permission "$CONFIG_DIR"; then
    echo "Attempting to fix permissions..."
    if sudo chown $USER:$(id -gn) "$CONFIG_DIR" 2>/dev/null && \
       sudo chmod 755 "$CONFIG_DIR" 2>/dev/null; then
        echo "✓ Permissions fixed"
    else
        echo "✗ Could not fix permissions. Exiting."
        exit 1
    fi
fi

check_disk_space "$CONFIG_DIR" 10 || exit 1

# Create configuration file
echo ""
echo "Creating configuration file: ${CONFIG_FILE}..."

cat > "$CONFIG_FILE" << CONFIG_EOF
#!/bin/bash
# snpEff Configuration - Version: ${CONFIG_VERSION}
# Generated by setup_snpeff_custom_paths.sh on $(date)
# Java: $JAVA_PATH
# snpEff: $SNPEFF_PATH

# Configuration version
export SNPEFF_CONFIG_VERSION="${CONFIG_VERSION}"

# Configuration paths (can be overridden by command line arguments)
export JAVA_HOME="\${1:-$JAVA_PATH}"
export SNPEFF_HOME="\${2:-$SNPEFF_PATH}"
export SNPEFF_MAX_MEM="\${3:-$MAX_MEM}"

# Update PATH
export PATH="\$JAVA_HOME/bin:\$PATH"

# Function to run snpEff
snpeff() {
    local java_path="\${SNPEFF_JAVA_HOME:-\$JAVA_HOME}"
    local snpeff_path="\${SNPEFF_JAR_PATH:-\$SNPEFF_HOME}"
    local mem="\${SNPEFF_MEM:-\$SNPEFF_MAX_MEM}"
    
    "\$java_path/bin/java" -Xmx\$mem -jar "\$snpeff_path/snpEff.jar" "\$@"
}

# Function to run snpSift
snpsift() {
    local java_path="\${SNPEFF_JAVA_HOME:-\$JAVA_HOME}"
    local snpeff_path="\${SNPEFF_JAR_PATH:-\$SNPEFF_HOME}"
    local mem="\${SNPEFF_MEM:-\$SNPEFF_MAX_MEM}"
    
    if [ ! -f "\$snpeff_path/SnpSift.jar" ]; then
        echo "Error: SnpSift.jar not found at \$snpeff_path/SnpSift.jar"
        return 1
    fi
    
    "\$java_path/bin/java" -Xmx\$mem -jar "\$snpeff_path/SnpSift.jar" "\$@"
}

# Display configuration when sourced
if [ -n "\$PS1" ]; then
    echo "snpEff environment loaded! (Version: ${CONFIG_VERSION})"
    echo "  Java: \$JAVA_HOME"
    echo "  snpEff: \$SNPEFF_HOME"
    echo "  Memory: \$SNPEFF_MAX_MEM"
    echo ""
    echo "Override paths with environment variables:"
    echo "  SNPEFF_JAVA_HOME, SNPEFF_JAR_PATH, SNPEFF_MEM"
fi
CONFIG_EOF

if [ $? -eq 0 ]; then
    chmod +x "$CONFIG_FILE" 2>/dev/null
    echo "✓ Configuration file created successfully"
else
    echo "✗ Failed to create configuration file"
    exit 1
fi

# Create/update symlink to current version
CURRENT_LINK="${CONFIG_DIR}/snpeff_current.sh"
echo ""
read -p "Set this as the current/default configuration? (y/n): " set_current
if [ "$set_current" = "y" ]; then
    ln -sf "$CONFIG_FILE" "$CURRENT_LINK"
    echo "✓ Set as current configuration (symlinked to snpeff_current.sh)"
fi

# Try to create wrapper scripts
WRAPPER_DIR="${CONFIG_DIR}/bin"
echo ""
echo "Creating wrapper scripts..."

if ! mkdir -p "$WRAPPER_DIR" 2>/dev/null; then
    echo "⚠ Cannot create wrapper directory without admin privileges"
    echo ""
    echo "  To create with admin privileges:"
    echo "    sudo mkdir -p $WRAPPER_DIR"
    echo "    sudo chown $USER:$(id -gn) $WRAPPER_DIR"
    echo ""
    WRAPPERS_CREATED=0
else
    # Create version-specific wrappers
    VERSIONED_WRAPPER_DIR="${WRAPPER_DIR}/${CONFIG_VERSION}"
    mkdir -p "$VERSIONED_WRAPPER_DIR" 2>/dev/null
    
    # snpEff wrapper that accepts path arguments
    SNPEFF_WRAPPER="$VERSIONED_WRAPPER_DIR/snpEff"
    cat > "$SNPEFF_WRAPPER" << 'WRAPPER_EOF'
#!/bin/bash
# snpEff wrapper script - autogenerated
# Version: VERSION_PLACEHOLDER
# Usage: snpEff [java_path] [snpeff_path] [memory] -- [snpeff arguments]

# Parse optional path arguments
if [[ "$1" != -* ]] && [ -d "$1" ]; then
    JAVA_PATH="$1"
    shift
else
    JAVA_PATH="${SNPEFF_JAVA_HOME:-${JAVA_HOME:-JAVA_PATH_PLACEHOLDER}}"
fi

if [[ "$1" != -* ]] && [ -d "$1" ]; then
    SNPEFF_PATH="$1"
    shift
else
    SNPEFF_PATH="${SNPEFF_JAR_PATH:-${SNPEFF_HOME:-SNPEFF_PATH_PLACEHOLDER}}"
fi

if [[ "$1" =~ ^[0-9]+[gGmM]$ ]]; then
    MEM="$1"
    shift
else
    MEM="${SNPEFF_MEM:-${SNPEFF_MAX_MEM:-MEMORY_PLACEHOLDER}}"
fi

# Skip -- separator if present
if [ "$1" = "--" ]; then
    shift
fi

# Run snpEff
"$JAVA_PATH/bin/java" -Xmx$MEM -jar "$SNPEFF_PATH/snpEff.jar" "$@"
WRAPPER_EOF
    
    # Replace placeholders with actual values
    sed -i "s|VERSION_PLACEHOLDER|$CONFIG_VERSION|g" "$SNPEFF_WRAPPER"
    sed -i "s|JAVA_PATH_PLACEHOLDER|$JAVA_PATH|g" "$SNPEFF_WRAPPER"
    sed -i "s|SNPEFF_PATH_PLACEHOLDER|$SNPEFF_PATH|g" "$SNPEFF_WRAPPER"
    sed -i "s|MEMORY_PLACEHOLDER|$MAX_MEM|g" "$SNPEFF_WRAPPER"
    chmod +x "$SNPEFF_WRAPPER" 2>/dev/null
    
    # snpSift wrapper that accepts path arguments
    SNPSIFT_WRAPPER="$VERSIONED_WRAPPER_DIR/snpSift"
    cat > "$SNPSIFT_WRAPPER" << 'WRAPPER_EOF'
#!/bin/bash
# snpSift wrapper script - autogenerated
# Version: VERSION_PLACEHOLDER
# Usage: snpSift [java_path] [snpeff_path] [memory] -- [snpsift arguments]

# Parse optional path arguments
if [[ "$1" != -* ]] && [ -d "$1" ]; then
    JAVA_PATH="$1"
    shift
else
    JAVA_PATH="${SNPEFF_JAVA_HOME:-${JAVA_HOME:-JAVA_PATH_PLACEHOLDER}}"
fi

if [[ "$1" != -* ]] && [ -d "$1" ]; then
    SNPEFF_PATH="$1"
    shift
else
    SNPEFF_PATH="${SNPEFF_JAR_PATH:-${SNPEFF_HOME:-SNPEFF_PATH_PLACEHOLDER}}"
fi

if [[ "$1" =~ ^[0-9]+[gGmM]$ ]]; then
    MEM="$1"
    shift
else
    MEM="${SNPEFF_MEM:-${SNPEFF_MAX_MEM:-MEMORY_PLACEHOLDER}}"
fi

# Skip -- separator if present
if [ "$1" = "--" ]; then
    shift
fi

# Check if SnpSift.jar exists
if [ ! -f "$SNPEFF_PATH/SnpSift.jar" ]; then
    echo "Error: SnpSift.jar not found at $SNPEFF_PATH/SnpSift.jar"
    exit 1
fi

# Run snpSift
"$JAVA_PATH/bin/java" -Xmx$MEM -jar "$SNPEFF_PATH/SnpSift.jar" "$@"
WRAPPER_EOF
    
    # Replace placeholders with actual values
    sed -i "s|VERSION_PLACEHOLDER|$CONFIG_VERSION|g" "$SNPSIFT_WRAPPER"
    sed -i "s|JAVA_PATH_PLACEHOLDER|$JAVA_PATH|g" "$SNPSIFT_WRAPPER"
    sed -i "s|SNPEFF_PATH_PLACEHOLDER|$SNPEFF_PATH|g" "$SNPSIFT_WRAPPER"
    sed -i "s|MEMORY_PLACEHOLDER|$MAX_MEM|g" "$SNPSIFT_WRAPPER"
    chmod +x "$SNPSIFT_WRAPPER" 2>/dev/null
    
    # Create symlinks in main bin directory if set as current
    if [ "$set_current" = "y" ]; then
        ln -sf "$SNPEFF_WRAPPER" "$WRAPPER_DIR/snpEff"
        ln -sf "$SNPSIFT_WRAPPER" "$WRAPPER_DIR/snpSift"
        echo "✓ Created current version symlinks in $WRAPPER_DIR"
    fi
    
    echo "✓ Version-specific wrapper scripts created in $VERSIONED_WRAPPER_DIR"
    WRAPPERS_CREATED=1
fi

# Create version switcher script
SWITCHER_SCRIPT="${CONFIG_DIR}/switch_snpeff_version.sh"
cat > "$SWITCHER_SCRIPT" << 'SWITCHER_EOF'
#!/bin/bash
# snpEff version switcher

CONFIG_DIR="$(dirname "$0")"

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo ""
    echo "Available versions:"
    for config in "$CONFIG_DIR"/snpeff_*_env.sh; do
        if [ -f "$config" ]; then
            basename=$(basename "$config")
            version=${basename%_env.sh}
            version=${version#snpeff_}
            
            # Check if it's current
            if [ -L "$CONFIG_DIR/snpeff_current.sh" ]; then
                current=$(readlink "$CONFIG_DIR/snpeff_current.sh" | xargs basename)
                if [ "$basename" = "$current" ]; then
                    echo "  * $version (current)"
                else
                    echo "    $version"
                fi
            else
                echo "    $version"
            fi
        fi
    done
    exit 1
fi

VERSION="$1"
CONFIG_FILE="$CONFIG_DIR/snpeff_${VERSION}_env.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration for version '$VERSION' not found"
    echo "File not found: $CONFIG_FILE"
    exit 1
fi

# Update symlink
ln -sf "$CONFIG_FILE" "$CONFIG_DIR/snpeff_current.sh"

# Update wrapper symlinks if they exist
if [ -d "$CONFIG_DIR/bin" ]; then
    if [ -f "$CONFIG_DIR/bin/$VERSION/snpEff" ]; then
        ln -sf "$CONFIG_DIR/bin/$VERSION/snpEff" "$CONFIG_DIR/bin/snpEff"
        ln -sf "$CONFIG_DIR/bin/$VERSION/snpSift" "$CONFIG_DIR/bin/snpSift"
    fi
fi

echo "Switched to snpEff version: $VERSION"
echo "To activate: source $CONFIG_DIR/snpeff_current.sh"
SWITCHER_EOF

chmod +x "$SWITCHER_SCRIPT" 2>/dev/null
echo "✓ Created version switcher script: $SWITCHER_SCRIPT"

# Final summary
echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Configuration Summary:"
echo "  Version/Name: ${CONFIG_VERSION}"
echo "  Java path: $JAVA_PATH"
echo "  snpEff path: $SNPEFF_PATH"
echo "  Max memory: $MAX_MEM"
echo "  Config file: $CONFIG_FILE"
if [ -L "$CURRENT_LINK" ]; then
    echo "  Current link: $CURRENT_LINK"
fi
if [ $WRAPPERS_CREATED -eq 1 ]; then
    echo "  Version wrappers: $VERSIONED_WRAPPER_DIR/{snpEff,snpSift}"
fi
echo ""
echo "To use this specific version:"
echo "  source $CONFIG_FILE"
echo "  snpeff -version"
echo ""
if [ -L "$CURRENT_LINK" ]; then
    echo "To use the current/default version:"
    echo "  source $CURRENT_LINK"
    echo ""
fi
echo "To switch between versions:"
echo "  $SWITCHER_SCRIPT <version>"
echo ""
if [ $WRAPPERS_CREATED -eq 1 ]; then
    echo "To use wrapper scripts:"
    echo "  # For current version:"
    echo "  export PATH=$WRAPPER_DIR:\$PATH"
    echo ""
    echo "  # For specific version:"
    echo "  export PATH=$VERSIONED_WRAPPER_DIR:\$PATH"
    echo ""
    echo "  # With custom paths:"
    echo "  snpEff /path/to/java /path/to/snpeff 8g -- -version"
    echo ""
fi
echo "Environment variables for runtime configuration:"
echo "  SNPEFF_JAVA_HOME - Override Java installation"
echo "  SNPEFF_JAR_PATH  - Override snpEff location"
echo "  SNPEFF_MEM       - Override memory allocation"
echo "  SNPEFF_CONFIG_BASE - Override config base directory"
echo ""

# List all available configurations
list_configurations "$CONFIG_DIR"

# Special instructions for shared installation
if [[ "$CONFIG_DIR" == "/ref/sahlab/software"* ]]; then
    echo "For all lab members to use this setup:"
    echo "  Add to ~/.bashrc:"
    echo "    source $CURRENT_LINK  # Always use current version"
    echo "    # OR"
    echo "    source $CONFIG_FILE  # Use specific version"
    echo ""
    if [ $WRAPPERS_CREATED -eq 1 ]; then
        echo "    export PATH=$WRAPPER_DIR:\$PATH"
    fi
    echo ""
    echo "Lab members can override paths without changing the shared config:"
    echo "  export SNPEFF_JAVA_HOME=/their/java/path"
    echo "  export SNPEFF_JAR_PATH=/their/snpeff/path"
    echo ""
else
    echo "Add to your ~/.bashrc for permanent setup:"
    echo "  source $CURRENT_LINK  # Always use current version"
    echo "  # OR"
    echo "  source $CONFIG_FILE  # Use specific version"
    if [ $WRAPPERS_CREATED -eq 1 ]; then
        echo "  export PATH=$WRAPPER_DIR:\$PATH"
    fi
    echo ""
fi

echo "✓ Setup completed successfully!"
