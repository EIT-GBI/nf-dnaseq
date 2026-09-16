#!/usr/bin/env bash
#SBATCH --job-name=index-reference
#SBATCH --partition=cpu
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=index-reference-%j.out
#
# Build the BWA index (and .fai, if missing) beside a reference FASTA.
#
#   sbatch scripts/index_reference.sbatch /path/to/genome.fasta
#
# Login nodes here have no container runtime, and `bwa index` needs roughly
# 5.5x the genome size in RAM, so this runs on a compute node. Bump --mem for
# a large genome: ~2G is plenty for a bacterial genome, a human reference
# wants ~20G.
#
# The pipeline can build the index itself via BWA_INDEX, but doing it here
# once means:
#   - the index sits beside the real reference, which is where Parabricks
#     looks for it (it resolves --ref to its real path)
#   - the CPU and GPU paths align against byte-identical index files
#   - it is built once rather than on every fresh run

set -euo pipefail

FASTA="${1:-}"
if [ -z "$FASTA" ]; then
    echo "usage: sbatch $0 <reference.fasta>" >&2
    exit 1
fi
if [ ! -f "$FASTA" ]; then
    echo "No such file: $FASTA" >&2
    exit 1
fi

FASTA=$(readlink -f "$FASTA")
REF_DIR=$(dirname "$FASTA")
REF_NAME=$(basename "$FASTA")

BWA_IMG='/mnt/lustre/containers/.staging/nf/cache/ghcr.io-eit-gbi-nf-mod-bwa-latest.img'
SAM_IMG='/mnt/lustre/containers/.staging/nf/cache/ghcr.io-eit-gbi-nf-mod-samtools-latest.img'
[ -f "$BWA_IMG" ] || BWA_IMG='docker://ghcr.io/eit-gbi/nf-mod-bwa:latest'
[ -f "$SAM_IMG" ] || SAM_IMG='docker://ghcr.io/eit-gbi/nf-mod-samtools:latest'

if ! command -v apptainer >/dev/null 2>&1; then
    echo "apptainer not found. Submit this with sbatch rather than running it on a login node." >&2
    exit 1
fi

echo "Reference: $FASTA"

if [ -e "${FASTA}.bwt" ]; then
    echo "BWA index already present, skipping"
else
    echo "Building BWA index"
    apptainer exec --bind "$REF_DIR" "$BWA_IMG" bwa index "$FASTA"
fi

if [ -e "${FASTA}.fai" ]; then
    echo "Samtools index (.fai) already present, skipping"
else
    echo "Building .fai"
    apptainer exec --bind "$REF_DIR" "$SAM_IMG" samtools faidx "$FASTA"
fi

echo
echo "Done. Files beside the reference:"
ls -la "$REF_DIR" | grep -- "$REF_NAME"
