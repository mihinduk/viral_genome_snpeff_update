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
        '--glsearch',        # Use FASTA for alignment (less memory than Infernal)
        '--cpu', '1',        # Use single CPU (compatible with --glsearch)
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
    ftr_files = list(vadr_path.glob("*.vadr.ftr"))
    
    if not ftr_files:
        print("Warning: No .ftr files found in VADR output")
        return pd.DataFrame()
    
    annotations = []
    
    for ftr_file in ftr_files:
        print(f"Parsing {ftr_file}")
        
        with open(ftr_file, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip header lines
                if not line or line.startswith('#'):
                    continue
                
                # Parse tab-delimited fields
                parts = line.split()
                if len(parts) >= 24:
                    # Extract relevant fields
                    seq_name = parts[1]
                    feature_type = parts[5]
                    feature_name = parts[6]
                    feature_length = parts[7]
                    strand = parts[11]
                    seq_coords = parts[23]
                    
                    # Skip if not CDS or mat_peptide
                    if feature_type not in ['CDS', 'mat_peptide', 'gene']:
                        continue
                    
                    # Parse coordinates (format: start..end:strand or multiple segments)
                    # Handle single and multi-segment features
                    coord_parts = seq_coords.split(',')
                    first_segment = coord_parts[0]
                    last_segment = coord_parts[-1]
                    
                    # Extract start from first segment
                    start_str = first_segment.split('..')[0]
                    # Extract end from last segment
                    end_str = last_segment.split('..')[1].replace(':+', '').replace(':-', '')
                    
                    try:
                        start = int(start_str)
                        end = int(end_str)
                        
                        # Clean up feature name (replace underscores with spaces)
                        product = feature_name.replace('_', ' ')
                        
                        # Create gene name from product
                        gene = ''
                        notes = ''
                        
                        # Check for frameshift indicators based on coordinate structure
                        # Multi-segment features indicate frameshifts
                        if len(coord_parts) > 1:
                            notes = 'frameshift_variant'
                            
                            # Extract frameshift positions from segment boundaries
                            frameshift_positions = []
                            for i in range(len(coord_parts) - 1):
                                seg1_end = coord_parts[i].split('..')[1].replace(':+', '').replace(':-', '')
                                seg2_start = coord_parts[i + 1].split('..')[0]
                                
                                # Frameshift position is at the junction
                                frameshift_positions.append(seg1_end)
                            
                            if frameshift_positions:
                                notes = f'frameshift_variant_pos_{",".join(frameshift_positions)}'
                        
                        if 'NS' in product.upper():
                            # Extract NS protein names
                            import re
                            ns_match = re.search(r'NS\d+[A-Z]?', product.upper())
                            if ns_match:
                                gene = ns_match.group()
                        elif 'capsid' in product.lower():
                            gene = 'C'
                        elif 'envelope' in product.lower():
                            gene = 'E'
                        elif 'membrane' in product.lower() and 'precursor' not in product.lower():
                            gene = 'M'
                        elif 'prM' in product or 'precursor' in product.lower():
                            gene = 'prM'
                        elif feature_type == 'gene':
                            gene = product
                        
                        annotations.append({
                            'start': start,
                            'end': end,
                            'strand': strand,
                            'type': feature_type,
                            'product': product,
                            'gene': gene,
                            'notes': notes
                        })
                    except (ValueError, IndexError) as e:
                        print(f"Skipping line due to parsing error: {e}")
                        continue
    
    if annotations:
        df = pd.DataFrame(annotations)
        # Sort by start position
        df = df.sort_values('start')
        return df
    else:
        return pd.DataFrame()

def create_annotation_tsv(vadr_output, output_file, fasta_file=None):
    """
    Create TSV file from VADR annotations for manual review.
    Format compatible with step2_add_to_snpeff.py
    
    Args:
        vadr_output: DataFrame with VADR annotations
        output_file: Path to output TSV file
        fasta_file: Path to input fasta file (to extract sequence ID)
    """
    if vadr_output.empty:
        print("No annotations to write")
        return
    
    # Get sequence ID from fasta file if provided
    seqid = 'genome'
    if fasta_file and os.path.exists(fasta_file):
        with open(fasta_file, 'r') as f:
            header = f.readline().strip()
            if header.startswith('>'):
                # Extract accession from header (first word after >)
                seqid = header[1:].split()[0]
    
    # Keep strand as +/- (no conversion needed)
    # VADR already provides correct +/- format
    
    # Convert mat_peptide to CDS for snpEff compatibility
    type_map = {'mat_peptide': 'CDS', 'CDS': 'CDS', 'gene': 'gene'}
    vadr_output['type_mapped'] = vadr_output['type'].map(type_map).fillna('CDS')
    
    # Generate unique IDs for each feature
    vadr_output['feature_id'] = vadr_output.apply(
        lambda row: f"{row.get('gene', 'feature')}_{row.name}" if row.get('gene') else f"feature_{row.name}",
        axis=1
    )
    
    # Prepare columns for output - matching format from step1_parse_viral_genome.py exactly
    output_df = pd.DataFrame({
        'action': 'KEEP',  # Match reference format
        'seqid': seqid,  # Use actual sequence ID
        'source': 'VADR',
        'type': vadr_output['type_mapped'],
        'start': vadr_output['start'],
        'end': vadr_output['end'],
        'strand': vadr_output['strand'],
        'gene_name': vadr_output.get('gene', ''),  # Editable gene name
        'product': vadr_output.get('product', ''),  # Original product
        'ID': vadr_output['feature_id'],
        'gene': vadr_output.get('gene', ''),  # Same as gene_name for compatibility
        'protein_id': '',  # Empty, can be filled if needed
        'notes': vadr_output.get('notes', '')  # Include frameshift notes
    })
    
    # Reorder columns to match reference format exactly
    output_df = output_df[['action', 'seqid', 'source', 'type', 'start', 'end', 'strand', 
                          'gene_name', 'product', 'ID', 'gene', 'protein_id', 'notes']]
    
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
            create_annotation_tsv(annotations, args.tsv, args.fasta)
        
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