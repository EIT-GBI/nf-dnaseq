# Changelog

All notable changes to `nf-dnaseq` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Samplesheet rows without `R1`/`R2` now also find their reads in a folder
  named after the sample, `<fastq_dir>/<sample>/`, the layout Element AVITI's
  `bases2fastq` writes (`Samples/<project>/<sample>/`). They used to fail with
  "found 0". The lookup uses `files()`, which removes Nextflow's warning about
  `file()` called with a glob.
- Every process now runs with `bash -euo pipefail`, so a task fails when any
  command in a pipe fails. Up to v1.3.0 a `bwa mem` crash or OOM-kill in
  `BWA_MEM` could still yield a truncated, cached BAM because `samtools sort`
  exited 0. v1.4.0 already fixed the piped modules themselves (nf-mod-bwa
  1.1.0, nf-mod-bcftools 1.1.0, nf-mod-samtools 1.2.0). Their changed scripts
  and containers make the first `-resume` of a run cached by v1.3.0 or earlier
  redo those steps once; after that, caching works as usual. This covers
  every other process, including local ones and future modules.

### Added

- Samplesheet `R1`/`R2` columns are optional when `fastq_dir` is set: rows
  without them find `<sample>_*R1*.fastq.gz` / `_*R2*` in `fastq_dir`.
- `manifest {}` block declaring the pipeline name, version and a minimum
  Nextflow version of 26.04.4.
- Defaults for every parameter, so the pipeline no longer requires a params
  file just to start up.
- `-profile test`: an end-to-end run on the nf-core sarscov2 dataset, fetched
  over HTTPS. Also `docker` and `apptainer` profiles.
- References lacking a BWA index are now indexed automatically via `BWA_INDEX`,
  rather than failing.
- `LICENSE` (MIT), `CHANGELOG.md`, `CITATIONS.md`.
- Continuous integration: linting, an end-to-end test run, and a stub run of
  the GPU path.

### Changed

- Results are published by a workflow `output {}` block in `main.nf` instead of
  `publishDir` directives inside each module. The published layout is unchanged,
  but the output directory now honours `-output-dir` / `-o`.
- Module processes no longer read pipeline `params`. Tool flags are passed via
  `task.ext.args` from `nextflow.config`.
- Reference helpers in `modules/utils/references.nf` take the reference
  directory as an argument rather than reading `params.reference_dir`.
- `params.cluster.yaml` no longer requests `deepvariant`. It ships with
  `bcftools` alone, matching the pipeline's own default in `nextflow.config`,
  so an unedited copy of that file no longer queues for GPU nodes. Uncomment
  `deepvariant` or `mutect2` to turn the Parabricks callers back on.
- Module submodules and their containers are pinned to release tags instead of
  floating commits and `:latest`.
- The automation workflows (`release.yml`, `auto-release.yml`,
  `sync-submodules.yml`, `flag-major-updates.yml`) use a token from the
  `eit-gbi-release-bot` GitHub App instead of the `NF_ORG_PAT` personal token,
  so the pushes to `main` can bypass the `main` ruleset and there is one
  credential to maintain.

### Fixed

- `-profile local` no longer interpolates a null `params.ucsc_dir` into `PATH`.
- Removed a stray debug `print(rows)` from `scripts/generate_samplesheet.py`.
- Parabricks GPU steps (`PARABRICKS_*`) now retry on exit status 255, a
  transient GPU failure seen with DeepVariant that succeeds on resume.
- A gzipped reference is now decompressed once, up front, and every process is
  handed the plain fasta. Parabricks parses the reference itself rather than
  reading the `.fai`, so with a bgzipped one `pbrun` saw only part of the
  contigs and failed with "does not contain chromosome ..." after alignment had
  already succeeded. The decompression happens in the work dir, so a run with a
  gzipped reference now works but pays for it each time; the run warns and
  points at `scripts/index_reference.sbatch`, which does it once.
- `scripts/index_reference.sbatch` decompresses a gzipped reference beside the
  original before indexing it, so the plain fasta and its indexes are both
  there for later runs.
