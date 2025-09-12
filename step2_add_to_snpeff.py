#!/usr/bin/env python3
'''
STEP 2: Add edited viral genome to snpEff database
Final version with proper unique IDs for each CDS
'''

import os
import sys
import argparse
import subprocess
import shutil
import pandas as pd
from pathlib import Path
from Bio import SeqIO
from Bio.SeqRecord import SeqRecord

def tsv_to_gff(tsv_file, gff_file):
    '''Convert edited TSV back to GFF3 format with unique IDs per CDS'''
    
    df = pd.read_csv(tsv_file, sep='\t')
    
    # Filter out rows marked for deletion
    df_keep = df[df['action'] != 'DELETE'].copy()
    
    # Count features by type
    feature_counts = df_keep['type'].value_counts()
    
    with open(gff_file, 'w') as f:
        # Write GFF3 header
        f.write('##gff-version 3\n')
        
        # Get sequence region from data
        if len(df_keep) > 0:
            seqid = df_keep.iloc[0]['seqid']
            max_end = df_keep['end'].max()
            f.write(f'##sequence-region {seqid} 1 {max_end}\n')
        
        # Keep track of CDS count for fallback IDs
        cds_count = 0
        
        # Write features
        for _, row in df_keep.iterrows():
            # Build basic GFF line
            gff_parts = [
                row['seqid'],
                row['source'],
                row['type'],
                str(row['start']),
                str(row['end']),
                '.',  # score
                row['strand'],
                '.',  # phase
            ]
            
            # Build attributes
            attributes = []
            
            # For CDS features, create unique ID based on gene name
            if row['type'] == 'CDS':
                cds_count += 1
                # Use gene name if available, otherwise use original ID or create one
                if pd.notna(row.get('gene_name')) and row['gene_name']:
                    unique_id = row['gene_name']
                elif pd.notna(row.get('ID')):
                    unique_id = f"CDS_{row['ID']}_{cds_count}"
                else:
                    unique_id = f"CDS_{cds_count}"
                
                attributes.append(f"ID={unique_id}")
                
                # Add gene name
                if pd.notna(row.get('gene_name')) and row['gene_name']:
                    attributes.append(f"gene={row['gene_name']}")
                
                # Add product
                if pd.notna(row.get('product')) and row['product']:
                    attributes.append(f"product={row['product']}")
                
                # Add protein_id
                if pd.notna(row.get('protein_id')) and row['protein_id']:
                    attributes.append(f"protein_id={row['protein_id']}")
                    
            else:
                # For non-CDS features, use original ID if present
                if pd.notna(row.get('ID')):
                    attributes.append(f"ID={row['ID']}")
                
                # Add other attributes as needed
                if pd.notna(row.get('gene_name')) and row['gene_name']:
                    attributes.append(f"gene={row['gene_name']}")
                
                if pd.notna(row.get('product')) and row['product']:
                    attributes.append(f"product={row['product']}")
            
            # Join attributes
            if attributes:
                gff_parts.append(';'.join(attributes))
            else:
                gff_parts.append('.')
            
            f.write('\t'.join(gff_parts) + '\n')
    
    print(f"Created GFF3 file from edited TSV: {gff_file}")
    print(f"  Total features: {len(df_keep)}")
    print(f"\nFeature summary:")
    for feat_type, count in feature_counts.items():
        print(f"  {feat_type}: {count}")

def extract_cds_and_proteins(genome_file, gff_file, cds_file, protein_file):
    '''Extract CDS and protein sequences from genome based on GFF coordinates'''
    
    # Read genome
    genome_record = SeqIO.read(genome_file, 'fasta')
    
    # Parse GFF and extract CDS features
    cds_records = []
    protein_records = []
    
    with open(gff_file, 'r') as f:
        for line in f:
            if line.startswith('#'):
                continue
                
            parts = line.strip().split('\t')
            if len(parts) >= 9 and parts[2] == 'CDS':
                start = int(parts[3]) - 1  # Convert to 0-based
                end = int(parts[4])
                strand = parts[6]
                attributes = parts[8]
                
                # Parse attributes
                attr_dict = {}
                for attr in attributes.split(';'):
                    if '=' in attr:
                        key, value = attr.split('=', 1)
                        attr_dict[key] = value
                
                # Get the unique CDS ID (which should now be based on gene name)
                cds_id = attr_dict.get('ID', 'unknown')
                gene_name = attr_dict.get('gene', cds_id)
                product = attr_dict.get('product', 'hypothetical protein')
                
                # Create transcript ID that matches the CDS ID in GFF
                # This is critical - snpEff needs these to match!
                transcript_id = f"TRANSCRIPT_{cds_id}"
                
                # Extract sequence
                cds_seq = genome_record.seq[start:end]
                if strand == '-':
                    cds_seq = cds_seq.reverse_complement()
                
                # Create CDS record
                cds_record = SeqRecord(
                    cds_seq, 
                    id=transcript_id, 
                    description=f"{product} [gene={gene_name}]"
                )
                cds_records.append(cds_record)
                
                # Translate to protein
                protein_seq = cds_seq.translate(to_stop=True)
                protein_record = SeqRecord(
                    protein_seq, 
                    id=transcript_id, 
                    description=f"{product} [gene={gene_name}] [{genome_record.id}]"
                )
                protein_records.append(protein_record)
    
    # Write CDS and protein files
    if cds_records:
        SeqIO.write(cds_records, cds_file, 'fasta')
        print(f"  Created {cds_file} with {len(cds_records)} CDS sequences")
        
        # Show sample IDs for verification
        print(f"  Sample CDS IDs:")
        for rec in cds_records[:3]:
            print(f"    - {rec.id}")
    
    if protein_records:
        SeqIO.write(protein_records, protein_file, 'fasta')
        print(f"  Created {protein_file} with {len(protein_records)} protein sequences")
    
    return len(cds_records) > 0

def add_genome_to_snpeff(genome_id, fasta_file, gff_file, snpeff_data_dir=None, force=False):
    '''Add a genome to snpEff database with CDS and protein files'''
    
    # Determine snpEff data directory
    if not snpeff_data_dir:
        snpeff_home = os.environ.get('SNPEFF_HOME')
        if not snpeff_home:
            print("ERROR: SNPEFF_HOME not set. Please source the snpEff configuration:")
            print("  export SCRATCH_DIR=/path/to/your/scratch")
            print("  source /ref/sahlab/software/snpeff_configs/snpeff_current.sh")
            return False
        snpeff_data_dir = os.path.join(snpeff_home, 'data')
    
    # Create genome directory
    genome_dir = os.path.join(snpeff_data_dir, genome_id)
    
    # Check if directory exists and handle force flag
    if os.path.exists(genome_dir):
        if force:
            print(f"Removing existing {genome_id} directory (--force flag used)...")
            shutil.rmtree(genome_dir)
        else:
            print(f"ERROR: Genome directory already exists: {genome_dir}")
            print("Use --force flag to overwrite existing genome")
            return False
    
    os.makedirs(genome_dir, exist_ok=True)
    
    # Copy files to snpEff structure
    sequences_file = os.path.join(genome_dir, 'sequences.fa')
    genes_file = os.path.join(genome_dir, 'genes.gff')
    cds_file = os.path.join(genome_dir, 'cds.fa')
    protein_file = os.path.join(genome_dir, 'protein.fa')
    
    print(f"\nCopying files to snpEff data directory...")
    shutil.copy(fasta_file, sequences_file)
    shutil.copy(gff_file, genes_file)
    
    print(f"  Genome directory: {genome_dir}")
    print(f"  Sequences: {sequences_file}")
    print(f"  Annotations: {genes_file}")
    
    # Extract CDS and protein sequences
    print(f"\nExtracting CDS and protein sequences...")
    if not extract_cds_and_proteins(fasta_file, gff_file, cds_file, protein_file):
        print("WARNING: No CDS features extracted. Database may not build correctly.")
    
    # Update snpEff.config
    config_file = os.path.join(os.path.dirname(snpeff_data_dir), 'snpEff.config')
    
    # Check if genome is already in config
    with open(config_file, 'r') as f:
        config_content = f.read()
    
    if f"{genome_id}.genome" not in config_content:
        # Add genome to config
        with open(config_file, 'a') as f:
            f.write(f"\n# {genome_id} - WNV with truncated polyproteins\n")
            f.write(f"{genome_id}.genome : {genome_id}\n")
        print(f"  Added {genome_id} to snpEff.config")
    else:
        print(f"\n  {genome_id} already in snpEff.config")
    
    # Build the database
    print(f"\nBuilding snpEff database for {genome_id}...")
    print("This may take a minute...")
    
    # Use direct Java command
    snpeff_home = os.environ.get('SNPEFF_HOME')
    java_home = os.environ.get('JAVA_HOME')
    
    if java_home and snpeff_home:
        cmd = f"{java_home}/bin/java -Xmx4g -jar {snpeff_home}/snpEff.jar build -gff3 -v {genome_id}"
    else:
        print("ERROR: JAVA_HOME or SNPEFF_HOME not set")
        return False
    
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    
    if result.returncode == 0:
        print("Database built successfully!")
        
        # Parse output for summary
        if "Protein coding transcripts" in result.stdout:
            for line in result.stdout.split('\n'):
                if "Protein coding transcripts" in line or "Total Errors" in line:
                    print(f"  {line.strip()}")
        
        return True
    else:
        print("❌ Error building database:")
        print(result.stderr)
        if result.stdout:
            # Show relevant error details
            for line in result.stdout.split('\n'):
                if "ERROR" in line or "FATAL" in line or "Transcript IDs" in line:
                    print(line)
        return False

def main():
    parser = argparse.ArgumentParser(
        description='STEP 2: Add edited viral genome to snpEff database (Final)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
This script converts an edited TSV file to GFF3 format and adds it to snpEff.
Each CDS will have a unique ID based on its gene name for proper annotation.

Prerequisites:
  1. You must have run step1_parse_viral_genome.py first
  2. You must have reviewed and edited the TSV file
  3. snpEff environment must be loaded:
     export SCRATCH_DIR=/path/to/your/scratch
     source /ref/sahlab/software/snpeff_configs/snpeff_current.sh

Examples:
  # Add genome using edited TSV
  python3 step2_add_to_snpeff_final.py NC_009942.1 NC_009942.1_no_polyprotein_fin.tsv
  
  # Force overwrite existing genome
  python3 step2_add_to_snpeff_final.py NC_009942.1 NC_009942.1_no_polyprotein_fin.tsv --force

After successful addition:
  You can use the genome for annotation:
    snpeff NC_009942.1 your_variants.vcf > annotated.vcf
    
  The output will include specific gene names (e.g., NS1, NS3, E) 
  rather than generic polyprotein IDs.
        """
    )
    
    parser.add_argument('genome_id', 
                       help='Genome ID (e.g., NC_009942.1)')
    parser.add_argument('tsv_file',
                       help='Path to edited TSV file')
    parser.add_argument('--fasta',
                       help='Path to FASTA file (default: genome_id.fasta)')
    parser.add_argument('--gff',
                       help='Output GFF file name (default: genome_id_final.gff3)')
    parser.add_argument('--data-dir',
                       help='snpEff data directory (default: auto-detect from SNPEFF_HOME)')
    parser.add_argument('--force', action='store_true',
                       help='Overwrite existing genome if present')
    
    args = parser.parse_args()
    
    # Check TSV file exists
    if not os.path.exists(args.tsv_file):
        print(f"Error: TSV file not found: {args.tsv_file}")
        sys.exit(1)
    
    # Determine FASTA file
    fasta_file = args.fasta if args.fasta else f"{args.genome_id}.fasta"
    if not os.path.exists(fasta_file):
        print(f"Error: FASTA file not found: {fasta_file}")
        print(f"\nMake sure you have run: download_ncbi_genome {args.genome_id}")
        sys.exit(1)
    
    # Determine output GFF name
    gff_file = args.gff if args.gff else f"{args.genome_id}_final.gff3"
    
    print("="*60)
    print("STEP 2: Add Edited Viral Genome to snpEff (Final)")
    print("="*60)
    
    print(f"\nGenome ID: {args.genome_id}")
    print(f"Input TSV: {args.tsv_file}")
    print(f"FASTA file: {fasta_file}")
    print(f"Output GFF: {gff_file}")
    
    # Convert TSV to GFF
    print("\n" + "-"*40)
    print("Converting edited TSV to GFF3...")
    print("-"*40)
    tsv_to_gff(args.tsv_file, gff_file)
    
    # Add to snpEff
    print("\n" + "-"*40)
    print("Adding genome to snpEff database...")
    print("-"*40)
    success = add_genome_to_snpeff(args.genome_id, fasta_file, gff_file, args.data_dir, args.force)
    
    if success:
        print("\n" + "="*60)
        print("SUCCESS!")
        print("="*60)
        print(f"\n✅ Genome {args.genome_id} has been added to snpEff")
        print(f"\nYou can now use it for variant annotation:")
        print(f"  snpeff {args.genome_id} your_variants.vcf > annotated.vcf")
        print(f"\nVariants will be annotated with specific gene names")
        print(f"(e.g., NS1, NS3, E) rather than generic polyprotein IDs.")
    else:
        print("\n" + "="*60)
        print("FAILED")
        print("="*60)
        print(f"\n❌ Failed to add {args.genome_id} to snpEff")
        print("\nTroubleshooting:")
        print("1. Check that snpEff environment is loaded")
        print("2. Check that CDS gene names are unique in your TSV")
        print("3. Check the error messages above")

if __name__ == '__main__':
    main()
