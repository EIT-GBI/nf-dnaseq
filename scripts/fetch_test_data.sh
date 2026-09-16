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
echo "The reference has no BWA index; the pipeline builds one with BWA_INDEX on"
echo "the first run and writes it to the work directory, leaving $ABS/genome untouched."
echo
echo "Run with:"
echo "  --samplesheet   $ABS/samplesheet.csv"
echo "  --reference_dir $ABS/genome"
