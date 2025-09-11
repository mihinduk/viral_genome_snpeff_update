# Viral Genome snpEff Setup

Comprehensive setup system for Java 21 and snpEff with version management for viral genomics pipelines.

## Documentation

- **[Installation Guide](INSTALLATION_README.md)**: Complete setup and configuration instructions  
- **[Genome Management Guide](GENOME_MANAGEMENT_README.md)**: Adding custom viral genomes to snpEff

## Quick Start

```bash
git clone https://github.com/mihinduk/viral_genome_snpeff_update.git
cd viral_genome_snpeff_update
./setup_snpeff_custom_paths.sh
```

## Current Working Setup (HTCF)

- **Java 21**: `/ref/sahlab/software/jdk-21.0.5+11`
- **snpEff 5.2f**: Configured with version management
- **Config**: `source /ref/sahlab/software/snpeff_configs/snpeff_current.sh`

## Features

✅ **Java 21 Installation** - Required for latest snpEff versions  
✅ **Version Management** - Multiple snpEff configurations with easy switching  
✅ **HPC-Optimized** - Shared lab environments with proper permissions  
✅ **Admin-Aware** - Helpful error messages with specific fix commands  
✅ **Flexible Configuration** - Runtime overrides via environment variables  

## Scripts

- `setup_snpeff_custom_paths.sh` - Main installation script with version management
- `install_java21_conda.sh` - Alternative conda Java installer  
- `snpeff_env.sh` - Example environment configuration

## Requirements

- **Java 21+** for snpEff 5.2e and later
- **Bash shell** environment
- **Write access** to installation directory

## Usage

### Interactive Setup
```bash
./setup_snpeff_custom_paths.sh
```

### Non-Interactive Setup  
```bash
./setup_snpeff_custom_paths.sh /path/to/java21 /path/to/snpeff
```

### Using Multiple Versions
```bash
# List available versions
/ref/sahlab/software/snpeff_configs/switch_snpeff_version.sh

# Switch versions
/ref/sahlab/software/snpeff_configs/switch_snpeff_version.sh 5.2f
```

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Acknowledgments

Built for the Handley Lab viral genomics pipeline at Washington University in St. Louis.
