# Changelog

All notable changes to `nf-dnaseq` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
- Module submodules and their containers are pinned to release tags instead of
  floating commits and `:latest`.

### Fixed

- `-profile local` no longer interpolates a null `params.ucsc_dir` into `PATH`.
- Removed a stray debug `print(rows)` from `scripts/generate_samplesheet.py`.
