#!/usr/bin/env bash
# Stage the nf-core sarscov2 test dataset locally and write a samplesheet
# pointing at it. Use on machines where the compute nodes have no internet
# access, so the pipeline never has to fetch anything itself.
#
#   ./scripts/fetch_test_data.sh /path/to/test-data
#
# Then run with:
#   --samplesheet   /path/to/test-data/samplesheet.csv
#   --reference_dir /path/to/test-data/genome

set -euo pipefail

DEST="${1:-}"
if [ -z "$DEST" ]; then
    echo "usage: $0 <destination-directory>" >&2
    exit 1
fi

BASE='https://raw.githubusercontent.com/nf-core/test-datasets/modules/data/genomics/sarscov2'

mkdir -p "$DEST/genome" "$DEST/fastq"

echo "Fetching reference into $DEST/genome"
for f in genome.fasta genome.fasta.fai; do
    curl -fsSL "$BASE/genome/$f" -o "$DEST/genome/$f"
    echo "  $f"
done

echo "Fetching reads into $DEST/fastq"
for f in test_1.fastq.gz test_2.fastq.gz test2_1.fastq.gz test2_2.fastq.gz; do
    curl -fsSL "$BASE/illumina/fastq/$f" -o "$DEST/fastq/$f"
    echo "  $f"
done

# Build the BWA index next to the reference, if we can. Pre-indexing keeps
# BWA_INDEX out of the run entirely, so the CPU and GPU paths align against
# byte-identical index files - which matters when comparing the two. It also
# matches how production references are stored.
#
# Parabricks resolves --ref to its real path and looks for the index beside
# that file, so having it here rather than in a work directory is the
# arrangement it expects.
BWA_IMAGE='ghcr.io/eit-gbi/nf-mod-bwa:latest'
CACHED_IMG='/mnt/lustre/containers/.staging/nf/cache/ghcr.io-eit-gbi-nf-mod-bwa-latest.img'

if [ -e "$DEST/genome/genome.fasta.bwt" ]; then
    echo "BWA index already present, leaving it alone"
elif command -v apptainer >/dev/null 2>&1; then
    echo "Building the BWA index with apptainer"
    if [ -f "$CACHED_IMG" ]; then IMG="$CACHED_IMG"; else IMG="docker://$BWA_IMAGE"; fi
    apptainer exec "$IMG" bwa index "$DEST/genome/genome.fasta"
elif command -v singularity >/dev/null 2>&1; then
    echo "Building the BWA index with singularity"
    singularity exec "docker://$BWA_IMAGE" bwa index "$DEST/genome/genome.fasta"
elif command -v docker >/dev/null 2>&1; then
    echo "Building the BWA index with docker"
    docker run --rm -v "$(cd "$DEST/genome" && pwd):/ref" -w /ref "$BWA_IMAGE" bwa index genome.fasta
elif command -v bwa >/dev/null 2>&1; then
    echo "Building the BWA index with the bwa on PATH"
    bwa index "$DEST/genome/genome.fasta"
else
    echo "No container runtime or bwa found; skipping the index." >&2
    echo "The pipeline will build one itself via BWA_INDEX." >&2
fi

# Absolute paths: Nextflow resolves samplesheet entries relative to the launch
# directory otherwise, which bites when submitting through SLURM.
ABS=$(cd "$DEST" && pwd)

cat > "$DEST/samplesheet.csv" <<CSV
sample,R1,R2,reference
SAMPLE1,$ABS/fastq/test_1.fastq.gz,$ABS/fastq/test_2.fastq.gz,genome.fasta
SAMPLE2,$ABS/fastq/test2_1.fastq.gz,$ABS/fastq/test2_2.fastq.gz,genome.fasta
CSV

echo
echo "Wrote $DEST/samplesheet.csv"
echo
if [ -e "$DEST/genome/genome.fasta.bwt" ]; then
    echo "The reference is indexed, so BWA_INDEX will not run and the CPU and GPU"
    echo "paths will align against the same index files."
else
    echo "The reference is NOT indexed; the pipeline will build one with BWA_INDEX."
fi
echo
echo "Run with:"
echo "  --samplesheet   $ABS/samplesheet.csv"
echo "  --reference_dir $ABS/genome"
