#!/usr/bin/env python3

"""
Generate samplesheet.csv from a directory of paired-end FASTQ files.

Usage:

"""

import argparse
from collections import defaultdict
import csv
import os
import re
import sys
from pathlib import Path


FASTQ_SUFFIXES = ('.fastq.gz', '.fq.gz', '.fastq', '.fq')


def find_fastq(input_dir: Path) -> list[Path]:
    """Find all FASTQ files in the input directory."""
    fastqs = []
    for suffix in FASTQ_SUFFIXES:
        fastqs.extend(input_dir.glob(f'*{suffix}'))
    return sorted(fastqs)

def strip_fastq_suffix(name: str) -> str:
    for suffix in FASTQ_SUFFIXES:
        if name.endswith(suffix):
            return name[:-len(suffix)]
    return name


def parse_pair(path: Path) -> tuple[str, str] | None:
    """Parse a FASTQ file path to extract the sample name and read number."""
    name = strip_fastq_suffix(path.name)
    match = re.match(r'(.+)_R([12])(?:_\d+)?$', name)
    if match:
        sample_name, read_num = match.groups()
        return sample_name, read_num
    else:
        print(f"Warning: Could not parse FASTQ file '{path}' (expected format: <sample>_R1.fastq.gz or <sample>_R2.fastq.gz)", file=sys.stderr)
        return None


def main():

    parser = argparse.ArgumentParser()
    parser.add_argument('--input_dir', type=Path, required=True, help='Directory containing FASTQ files')
    parser.add_argument('--reference', type=Path, required=True, help='Path to reference genome FASTA file')
    parser.add_argument('--output', type=Path, default=Path('samplesheet.csv'), help='Output CSV file (default: samplesheet.csv)')
    args = parser.parse_args()

    input_dir = args.input_dir.resolve()
    if not input_dir.is_dir():
        print(f"Error: Input directory '{input_dir}' does not exist or is not a directory.", file=sys.stderr)
        sys.exit(1)

    # Resolve to absolute path, otherwise it'll parse nextflows work dir. ask me how I know
    reference = args.reference.resolve()
    if not reference.is_file():
        print(f"Error: Reference genome file '{reference}' does not exist or is not a file.", file=sys.stderr)
        sys.exit(1)

    fastqs = find_fastq(input_dir=input_dir)
    if not fastqs:
        print(f"Error: No FASTQ files found in directory '{input_dir}'.", file=sys.stderr)
        sys.exit(1)

    pairs: dict[str, dict[str, Path]] = defaultdict(dict)
    for fq in fastqs:
        parsed = parse_pair(fq)
        if parsed is None:
            print(f'warning: skipping unrecognized FASTQ file {fq}', file=sys.stderr)
            continue
        sample_name, read_num = parsed
        pairs[sample_name][f'R{read_num}'] = fq
        
    rows = []

    for sample in sorted(pairs):
        reads = pairs[sample]
        if 'R1' not in reads or 'R2' not in reads:
            print(f"Warning: Sample '{sample}' is missing R1 or R2 FASTQ file. Skipping.", file=sys.stderr)
            continue
        rows.append({
            'sample': sample,
            'R1': reads['R1'],
            'R2': reads['R2'],
            'reference': reference
        })
    print(rows)
    if not rows:
        print("Error: No valid sample pairs found. Exiting.", file=sys.stderr)
        sys.exit(1)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=['sample', 'R1', 'R2', 'reference'])
        writer.writeheader()
        writer.writerows(rows)

if __name__ == '__main__':
    main()
    