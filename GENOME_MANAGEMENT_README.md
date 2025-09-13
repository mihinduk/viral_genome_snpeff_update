# snpEff Genome Management Guide

Guide for adding custom viral genomes and databases to snpEff for annotation.

## Overview

This guide covers how to add custom viral genomes to snpEff, create custom databases, and manage genome annotations for viral genomics pipelines.

## Available Scripts

### Step 1: Genome Annotation (Choose One)

#### Option A: Parse GenBank Files
```bash
python3 step1_parse_viral_genome.py input.gbk
```
- Parses GenBank files to extract gene annotations
- Creates editable TSV file for manual review
- Handles polyproteins and complex annotations

#### Option B: VADR Annotation (NEW)
```bash
python3 step1_vadr_annotate.py input.fasta -o vadr_output --tsv annotations.tsv
```
- Uses VADR (Viral Annotation DefineR) for automated annotation
- Supports multiple virus families (Flavivirus, Calicivirus, Coronavirus, Mpox)
- Auto-detects virus family or specify with `--model`
- Creates TSV file compatible with step2

**VADR Features:**
- Auto-detection of virus family from FASTA headers
- Support for WNV, DENV, ZIKV, YFV, norovirus, SARS-CoV-2, mpox
- High-quality annotations based on reference models
- Validation and error checking

### Step 2: Add to snpEff
```bash
python3 step2_add_to_snpeff.py annotations.tsv reference.fasta
```
- Takes TSV from step1 (either version) and adds genome to snpEff
- Creates custom snpEff database
- Handles database configuration and validation

## VADR Integration

VADR provides high-quality viral genome annotation using curated reference models.

## Current Status

The installation system is complete and working. Genome management documentation will be added next.

## See Also

- **[Installation Guide](INSTALLATION_README.md)**: Setup Java 21 and snpEff
- **snpEff Manual**: https://pcingola.github.io/SnpEff/snpeff/inputoutput/
- **snpEff Database Building**: https://pcingola.github.io/SnpEff/snpeff/build_db/

## Future Features

- Automated genome annotation pipeline
- Support for viral genome variants
- Integration with NCBI viral genomes
- Custom annotation workflows for novel viruses