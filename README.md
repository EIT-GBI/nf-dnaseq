# nf-dnaseq

A Nextflow pipeline for DNA-seq analysis of paired-end short reads: read trimming, QC, alignment, coverage tracks, and variant calling. It runs on a SLURM cluster with Apptainer containers, and supports both **CPU** (bwa + samtools + bcftools) and **GPU** (NVIDIA Parabricks) execution paths.

This guide is written for researchers who want to run the pipeline on their own data on the cluster.

---

## What the pipeline does

```mermaid
flowchart TD
    A[FASTQ files] --> B[PREPARE_SAMPLESHEET<br/><i>build samplesheet.csv</i>]
    B --> C[FASTP_TRIM<br/><i>adapter/quality trimming</i>]
    C --> D[FASTQC_FASTQC<br/><i>read QC</i>]
    C --> E{alignment.device}

    E -->|cpu| F[BWA_MEM + SAMTOOLS_INDEX]
    E -->|gpu| G[PARABRICKS_FQ2BAM<br/><i>GPU alignment</i>]

    F --> H[sorted BAM + index]
    G --> H

    H --> I[SAMTOOLS_FLAGSTAT<br/><i>alignment metrics</i>]
    H --> J[BEDTOOLS_BIGWIG<br/><i>coverage track</i>]
    H --> K{variant_callers}

    K -->|bcftools| L[BCFTOOLS_CALL → VCF / CSV / CONSENSUS<br/><i>CPU</i>]
    K -->|deepvariant| M[PARABRICKS_DEEPVARIANT<br/><i>GPU</i>]
    K -->|mutect2| N[PARABRICKS_MUTECTCALLER<br/><i>GPU</i>]
```

**Execution paths at a glance:**

| Stage | CPU option | GPU option |
|---|---|---|
| Alignment | `bwa mem` + `samtools` | Parabricks `fq2bam` |
| Germline calling | `bcftools` | Parabricks `deepvariant` |
| Somatic calling | — | Parabricks `mutectcaller` (`mutect2`) |

> **Note:** `deepvariant` and `mutect2` are **GPU-only** (Parabricks), regardless of `alignment.device`. If you request either of those callers, the run needs GPU nodes even if you aligned on CPU. `bcftools` is CPU-only.

---

## One-time cluster setup

Do these once per checkout. Most first-run problems come from skipping one of them.

### 1. Clone **with submodules**

The entire pipeline uses tool modules (fastp, bwa, samtools, fastqc, bedtools, bcftools, parabricks).  These are technically git **submodules**, meaning that they live in their own github repositories and are just imported into this repository. A plain `git clone` will fail, as it leaves the module folders empty and Nextflow will fail. We need the `--recurse-submodules` flag to clone the modules too:

```bash
git clone --recurse-submodules https://github.com/eit-gbi/nf-dnaseq.git
cd nf-dnaseq
```

Some module repos are **private** (e.g. parabricks, bcftools). If prompted for a GitHub username/password, you need a **Personal Access Token**. #TODO: add instructions for creating a PAT. 

### 2. Add params information for your data

There is a section below on various ways to provide your inputs (FASTQ files, reference genome, etc.). The easiest is to open `params.cluster.yaml` and edit it for your data.

### 3. Run on the cluster

Run the command below from the **login node**. It will submit jobs to the SLURM scheduler and run the pipeline on compute nodes. The `-resume` flag is safe to include; it reuses cached results from previous runs.

```bash
nextflow run main.nf -params-file params.cluster.yaml -profile cluster -resume
```

---

## Preparing your inputs

You give the pipeline reads in one of **two ways**:

### Option A — point it at a FASTQ directory (easiest)

Set `fastq_dir` and `reference_genome`; the pipeline builds the samplesheet for you. FASTQ files must be paired and named:

```
<sample>_R1[_001].fastq.gz
<sample>_R2[_001].fastq.gz
```

(Accepted suffixes: `.fastq.gz`, `.fq.gz`, `.fastq`, `.fq`. The trailing `_001` is optional.)

### Option B — provide your own samplesheet

Set `samplesheet` to a CSV with these columns:

```csv
sample,R1,R2,reference
SAMPLE_A,/abs/path/A_R1.fastq.gz,/abs/path/A_R2.fastq.gz,mouse/genome.fasta
```

`reference` is a path **relative to `reference_dir`** (see below).

### Reference genome layout

References live under `reference_dir`, and `reference_genome` is the path **relative** to it. For example, with:

```yaml
reference_dir: "/mnt/gbi-shared/.../references/"
reference_genome: "mouse/MDS42_r24-30_27B_SC.fasta"
```

the pipeline resolves `/mnt/gbi-shared/.../references/mouse/MDS42_r24-30_27B_SC.fasta`.

Each reference **must be pre-indexed**. Alongside the `.fasta` you need:

| File(s) | Needed for |
|---|---|
| `*.fasta.fai` | samtools faidx (variant calling, bigwig) |
| `*.fasta.{amb,ann,bwt,pac,sa}` | bwa index (used by **both** CPU and GPU alignment) |

Build them once with `bwa index genome.fasta` and `samtools faidx genome.fasta`. #todo do indexing automatically if missing.

---

## Running on the cluster

```bash
nextflow run main.nf -params-file params.cluster.yaml -profile cluster -resume
```

- `-profile cluster` → SLURM executor + Apptainer containers.
- `-params-file params.cluster.yaml` → your inputs and settings.
- `-resume` → reuse cached results from previous runs (always safe to include).

Copy `params.cluster.yaml` and edit it for your data. Key parameters:

| Parameter | Meaning |
|---|---|
| `samplesheet` | Path to a samplesheet CSV, or `null` to build one from `fastq_dir` |
| `fastq_dir` | Directory of paired FASTQs (used when `samplesheet: null`) |
| `reference_genome` | Reference FASTA, **relative to** `reference_dir` |
| `reference_dir` | Root directory holding reference genomes + indexes |
| `outdir` | Where published results go |
| `alignment.device` | `cpu` (bwa/samtools) or `gpu` (Parabricks fq2bam) |
| `trimmer` | `fastp` (`cutadapt` not yet implemented) |
| `variant_callers` | List: any of `bcftools`, `deepvariant`, `mutect2` |
| `min_mapq`, `min_qual`, `min_depth`, `ploidy` | bcftools calling/filtering thresholds |
| `ucsc_dir` | Only for **local** runs (path to `bedGraphToBigWig`); ignored on the cluster |

Example `variant_callers` block (YAML list — comment/uncomment to choose):

```yaml
variant_callers:
  - bcftools
  - deepvariant
#  - mutect2
```

---

## Overriding parameters

A parameter can be set in three places. They form **layers**, and higher layers win:

```mermaid
flowchart TD
    C["<b>Command line --flags</b><br/><i>highest priority — always wins</i>"]
    B["<b>-params-file params.cluster.yaml</b><br/>your run's settings"]
    A["<b>nextflow.config</b><br/>defaults & profiles<br/><i>lowest priority</i>"]

    C -->|overrides| B
    B -->|overrides| A

    style C fill:#f7e6d0,stroke:#c98a3a
    style B fill:#dbeadb,stroke:#4a8a4a
    style A fill:#e8eef7,stroke:#4a6fa5
```

> **config  <  params-file  <  command line**

So you can keep a stable `params.cluster.yaml` and tweak individual runs on the command line without editing files.

### Examples

Switch to the GPU alignment path for one run:

```bash
nextflow run main.nf -params-file params.cluster.yaml -profile cluster \
  --alignment.device gpu -resume
```

Change calling thresholds on the fly:

```bash
nextflow run main.nf -params-file params.cluster.yaml -profile cluster \
  --min_depth 20 --min_qual 30 -resume
```

Choose variant callers from the command line (comma-separated, **no spaces**):

```bash
nextflow run main.nf -params-file params.cluster.yaml -profile cluster \
  --variant_callers bcftools,deepvariant,mutect2 -resume
```

**Gotchas:**
- Nested params use dotted notation: `--alignment.device gpu` (not `--device`, which is unused).
- List params (`variant_callers`) must be a **comma-separated string** on the CLI — the pipeline splits it. You **cannot** repeat `--variant_callers` to add items; the last one wins.
- Scalars (numbers, strings, `cpu`/`gpu`) work directly on the CLI.

---

## Outputs

Results are published under `outdir`:

```
outdir/
├── samplesheet/          # generated samplesheet.csv
├── trimmed/              # fastp reports (html/json)
├── qc/
│   ├── fastqc/           # FastQC reports
│   └── flagstat/         # samtools flagstat metrics
├── alignment/            # sorted BAM + index
├── bigwig/               # coverage tracks (.bw)
└── variants/
    ├── bcf/  vcf/  csv/   # bcftools outputs
    ├── consensus/         # consensus FASTA
    ├── deepvariant/       # DeepVariant VCFs (GPU)
    └── mutect/            # Mutect2 VCFs (GPU)
```

---

## GPU notes

The `cluster` profile requests GPUs for all Parabricks steps:

```groovy
withName: 'PARABRICKS_.*' {
    accelerator      = 2
    clusterOptions   = '--gres=gpu:2'   // must match accelerator / --num-gpus
    queue            = 'gpu'
    containerOptions = '--nv'           // exposes host GPUs to the container
}
```

Keep the **GPU count consistent** across `--gres`, `accelerator`, and the tool's `--num-gpus` (the modules derive `--num-gpus` from `accelerator` automatically). #todo make them match automatically if the user sets `--num-gpus` on the CLI.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `Invalid include source: .../modules/...` | Submodules not checked out → `git submodule update --init --recursive` |
| GitHub `403` on `git submodule update` | Private repo; use a PAT with `repo` scope, authorize for SSO |
| `mksquashfs … exit status 139` | #todo pin an exact fix for this. Apptainer is probably out of temp space → set `APPTAINER_TMPDIR` to local scratch with more space and ensure `APPTAINER_CACHEDIR` is also set |


## TODO list
- [ ] Add `cutadapt` trimmer option.
- [ ] Add 'gatk' variant caller option.
- [ ] Add tmux instructions for cluster runs.
- [ ] Add produce csvs for all variant callers. Easy for inspection.

