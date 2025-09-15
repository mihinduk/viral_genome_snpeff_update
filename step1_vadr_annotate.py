#!/usr/bin/env python3
"""
STEP 1 (Alternative): Run VADR annotation on viral genome sequences.
This script runs VADR (Viral Annotation DefineR) to annotate viral genomes
and extracts annotation information for downstream processing.
Can be used as an alternative to step1_parse_viral_genome.py.
"""

import sys
import os
import argparse
import subprocess
import pandas as pd
from pathlib import Path
from Bio import SeqIO
import json
import re

# VADR model configurations for different virus families
VADR_MODELS = {
    'flavi': {
        'mdir': '/ref/sahlab/software/envs/vadr_env/share/vadr-1.6.4/vadr-models',
        'mkey': 'flavi',
        'viruses': ['WNV', 'DENV', 'ZIKV', 'YFV', 'JEV', 'TBEV', 'SLEV']
    },
    'dengue': {
        'mdir': '/ref/sahlab/software/envs/vadr_env/share/vadr-1.6.4/vadr-models',
        'mkey': 'dengue',
        'viruses': ['DENV', 'DENGUE']
    },
    'sarscov2': {
        'mdir': '/ref/sahlab/software/envs/vadr_env/share/vadr-1.6.4/vadr-models',
        'mkey': 'sarscov2',
        'viruses': ['SARS-CoV-2', 'COVID', 'CORONAVIRUS']
    },
    'hcv': {
        'mdir': '/ref/sahlab/software/envs/vadr_env/share/vadr-1.6.4/vadr-models',
        'mkey': 'hcv',
        'viruses': ['HCV', 'HEPATITIS C']
    }
}

def detect_virus_family(fasta_file, accession=None):
    """
    Detect virus family from fasta header or accession.
    
    Args:
        fasta_file: Path to fasta file
        accession: Optional accession number
        
    Returns:
        Virus family key for VADR models
    """
    # Read first sequence header
    with open(fasta_file, 'r') as f:
        header = f.readline().strip()
    
    header_upper = header.upper()
    
    # Check for virus keywords in header
    for family, config in VADR_MODELS.items():
        for virus in config['viruses']:
            if virus.upper() in header_upper:
                print(f"Detected {virus} - using {family} model")
                return family
    
    # If no match found, exit with helpful message
    print(f"Could not auto-detect virus family from header: {header}")
    print("")
    print("ERROR: Virus family must be specified with --model")
    print("")
    print("Available virus families:")
    for key, config in VADR_MODELS.items():
        print(f"  --model {key}  # {', '.join(config['viruses'])}")
    print("")
    print("Example:")
    print(f"  python3 {sys.argv[0]} {sys.argv[1]} --model flavi -o output_dir")
    
    return None

def run_vadr(fasta_file, output_dir, model_family, force=False):
    """
    Run VADR annotation on a fasta file.
    
    Args:
        fasta_file: Path to input fasta file
        output_dir: Output directory for VADR results
        model_family: Virus family for model selection
        force: Force overwrite of output directory
        
    Returns:
        Path to VADR output directory
    """
    if model_family not in VADR_MODELS:
        raise ValueError(f"Unknown model family: {model_family}")
    
    model_config = VADR_MODELS[model_family]
    
    # Build VADR command with memory-friendly options
    cmd = [
        '/ref/sahlab/software/micromamba', 'run', '-p', '/ref/sahlab/software/envs/vadr_env',
        'v-annotate.pl',
        str(fasta_file),
        '--mdir', model_config['mdir'],
        '--mkey', model_config['mkey'],
        '--split',           # Split sequences for memory-efficient processing
        '--cpu', '1',        # Use single CPU (compatible with --split)
        str(output_dir)
    ]
    
    if force:
        cmd.insert(-1, '-f')
    
    print(f"Running VADR with command:")
    print(' '.join(cmd))
    
    # Run VADR
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print("VADR error output:", result.stderr)
        raise RuntimeError(f"VADR failed with return code {result.returncode}")
    
    print("VADR completed successfully")
    return output_dir

def parse_vadr_output(vadr_dir):
    """
    Parse VADR output files to extract annotation information.
    
    Args:
        vadr_dir: Path to VADR output directory
        
    Returns:
        DataFrame with annotation information
    """
    vadr_path = Path(vadr_dir)
    
    # Parse the .ftr file for feature information
    ftr_files = list(vadr_path.glob("*.vadr.pass.tbl"))
    if not ftr_files:
        ftr_files = list(vadr_path.glob("*.vadr.fail.tbl"))
    
    if not ftr_files:
        print("Warning: No .tbl files found in VADR output")
        return pd.DataFrame()
    
    annotations = []
    
    for ftr_file in ftr_files:
        print(f"Parsing {ftr_file}")
        current_feature = {}
        
        with open(ftr_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('>'):
                    continue
                
                parts = line.split('\t')
                if len(parts) >= 3:
                    # Parse coordinates and feature type
                    coords = parts[0]
                    feature_type = parts[2] if len(parts) > 2 else ''
                    
                    # Skip if not CDS or mat_peptide
                    if feature_type not in ['CDS', 'mat_peptide']:
                        continue
                    
                    # Parse coordinates
                    if '..' in coords:
                        start, end = coords.split('..')
                        # Handle complement annotations
                        if coords.startswith('complement('):
                            coords_clean = coords.replace('complement(', '').replace(')', '')
                            start, end = coords_clean.split('..')
                            strand = '-'
                        else:
                            strand = '+'
                        
                        # Remove < or > symbols
                        start = start.replace('<', '').replace('>', '')
                        end = end.replace('<', '').replace('>', '')
                        
                        current_feature = {
                            'start': int(start),
                            'end': int(end),
                            'strand': strand,
                            'type': feature_type
                        }
                
                # Look for qualifiers
                if current_feature and '\t\t\t' in line:
                    qualifier_line = line.strip()
                    if 'product' in qualifier_line:
                        product = qualifier_line.split('product')[1].strip()
                        current_feature['product'] = product
                    elif 'gene' in qualifier_line:
                        gene = qualifier_line.split('gene')[1].strip()
                        current_feature['gene'] = gene
                    
                    # If we have enough info, save the feature
                    if 'product' in current_feature:
                        annotations.append(current_feature.copy())
                        current_feature = {}
    
    if annotations:
        df = pd.DataFrame(annotations)
        # Sort by start position
        df = df.sort_values('start')
        return df
    else:
        return pd.DataFrame()

def create_annotation_tsv(vadr_output, output_file):
    """
    Create TSV file from VADR annotations for manual review.
    Format compatible with step2_add_to_snpeff.py
    
    Args:
        vadr_output: DataFrame with VADR annotations
        output_file: Path to output TSV file
    """
    if vadr_output.empty:
        print("No annotations to write")
        return
    
    # Prepare columns for output - matching format from step1_parse_viral_genome.py
    output_df = pd.DataFrame({
        'seqid': 'genome',  # Default sequence ID
        'source': 'VADR',
        'type': vadr_output['type'],
        'start': vadr_output['start'],
        'end': vadr_output['end'],
        'score': '.',
        'strand': vadr_output['strand'],
        'phase': '0',  # Default phase for CDS
        'attributes': vadr_output.apply(
            lambda row: f"ID={row.get('gene', 'gene')};Name={row.get('gene', row.get('product', 'unknown'))};product={row.get('product', '')}",
            axis=1
        ),
        'gene_name': vadr_output.get('gene', ''),  # Editable gene name
        'product': vadr_output.get('product', ''),  # Original product
        'notes': ''  # For manual notes
    })
    
    # Save to TSV
    output_df.to_csv(output_file, sep='\t', index=False)
    print(f"Annotation TSV saved to: {output_file}")
    print(f"You can now edit this file and run step2_add_to_snpeff.py")

def main():
    parser = argparse.ArgumentParser(
        description='STEP 1 Alternative: Run VADR annotation on viral genomes',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
This is an alternative to step1_parse_viral_genome.py that uses VADR for annotation.

Examples:
  # Auto-detect virus family
  %(prog)s input.fasta -o vadr_output
  
  # Specify virus family
  %(prog)s WNV_genome.fasta -o WNV_vadr --model flavi
  
  # Create annotation TSV for review (compatible with step2_add_to_snpeff.py)
  %(prog)s input.fasta -o vadr_output --tsv annotations.tsv
  
  # Force overwrite existing output
  %(prog)s input.fasta -o vadr_output --tsv annotations.tsv -f
        """
    )
    
    parser.add_argument('fasta', help='Input FASTA file')
    parser.add_argument('-o', '--output', required=True, help='Output directory for VADR results')
    parser.add_argument('--model', choices=list(VADR_MODELS.keys()), 
                       help='Virus family model to use (auto-detect if not specified)')
    parser.add_argument('--tsv', help='Output TSV file for annotation review (compatible with step2)')
    parser.add_argument('-f', '--force', action='store_true', 
                       help='Force overwrite of output directory')
    parser.add_argument('--skip-vadr', action='store_true',
                       help='Skip VADR run and just parse existing output')
    
    args = parser.parse_args()
    
    # Check input file
    if not os.path.exists(args.fasta) and not args.skip_vadr:
        print(f"Error: Input file {args.fasta} not found")
        sys.exit(1)
    
    try:
        # Detect or validate virus family
        if not args.model and not args.skip_vadr:
            model_family = detect_virus_family(args.fasta)
            if not model_family:
                sys.exit(1)
        else:
            model_family = args.model
        
        # Run VADR unless skipped
        if not args.skip_vadr:
            vadr_dir = run_vadr(args.fasta, args.output, model_family, args.force)
        else:
            vadr_dir = args.output
            if not os.path.exists(vadr_dir):
                print(f"Error: VADR output directory {vadr_dir} not found")
                sys.exit(1)
        
        # Parse VADR output
        annotations = parse_vadr_output(vadr_dir)
        
        if not annotations.empty:
            print(f"\nFound {len(annotations)} annotations:")
            print(annotations[['type', 'start', 'end', 'product']].to_string())
        
        # Create TSV if requested
        if args.tsv:
            create_annotation_tsv(annotations, args.tsv)
        
        print(f"\nVADR annotation complete. Output in: {vadr_dir}")
        
        if args.tsv:
            print(f"\nNext steps:")
            print(f"1. Review and edit the TSV file: {args.tsv}")
            print(f"2. Run step2_add_to_snpeff.py to add annotations to snpEff")
        
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()