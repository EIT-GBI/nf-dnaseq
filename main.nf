#!/usr/bin/env nextflow

//
// Modules loaded from local dir
//
include {PREPARE_SAMPLESHEET} from './modules/samplesheet/prepare/main.nf'

//
// Modules loaded from nf-mod-repos
//
include {FASTP_TRIM} from './modules/fastp/trim/main.nf'
include {FASTQC_FASTQC} from './modules/fastqc/fastqc/main.nf'
include {BWA_INDEX} from './modules/bwa/index/main.nf'
include {BWA_MEM} from './modules/bwa/mem/main.nf'
include {SAMTOOLS_INDEX} from './modules/samtools/index/main.nf'
include {SAMTOOLS_FAIDX} from './modules/samtools/faidx/main.nf'
include {SAMTOOLS_FLAGSTAT} from './modules/samtools/flagstat/main.nf'
include {PARABRICKS_FQ2BAM} from './modules/parabricks/fq2bam/main.nf'
include {PARABRICKS_DEEPVARIANT} from './modules/parabricks/deepvariant/main.nf'
include {PARABRICKS_MUTECTCALLER} from './modules/parabricks/mutectcaller/main.nf'
include {BEDTOOLS_BIGWIG} from './modules/bedtools/bigwig/main.nf'
include {BCFTOOLS_CONSENSUS} from './modules/bcftools/consensus/main.nf'
include {BCFTOOLS_CALL} from './modules/bcftools/call/main.nf'
include {BCFTOOLS_CSV} from './modules/bcftools/csv/main.nf'
include {BCFTOOLS_VCF} from './modules/bcftools/vcf/main.nf'
include {refFasta; bwaIndexFor; bwaIndexExists; faidxFor; faidxExists} from './modules/utils/references.nf'


workflow {

    main:

    // Some basic checks on the input parameters
    if (!(params.alignment.device in ['cpu', 'gpu'])){
        error "Invalid value for params.alignment.device: ${params.alignment.device}. Use 'cpu' for bwa+samtools or 'gpu' for Parabricks."
    }

    if (!(params.trimmer in ['fastp', 'cutadapt'])){
        error "Invalid value for params.trimmer: ${params.trimmer}. Use 'fastp' or 'cutadapt'."
    }

    if (!params.reference_dir) {
        error "You must set params.reference_dir: the directory holding the reference genomes."
    }

    // Check if a samplesheet is provided, otherwise build one from the fastq directory and reference genome
    if (params.samplesheet) {
        samplesheet_ch = channel.fromPath(params.samplesheet, checkIfExists: true)
    }
    else if (params.fastq_dir && params.reference_genome) {
        PREPARE_SAMPLESHEET(
            file("${projectDir}/" + params.scripts.py_samplesheet), 
            file(params.fastq_dir), 
            params.reference_genome
            )
        samplesheet_ch = PREPARE_SAMPLESHEET.out.csv
    }
    else {
        error "You must provide either a samplesheet or a fastq directory and reference genome."
    }

    // Parse the variant callers parameter into a list
    def callers = (params.variant_callers instanceof List)
        ? params.variant_callers
        : "${params.variant_callers}".tokenize(',')*.trim()

    def reference_dir = params.reference_dir

    // Publishable channels that only some branches produce. Declared up front so
    // the publish: section below always has something to assign.
    ch_trim_html   = channel.empty()
    ch_trim_log    = channel.empty()
    ch_dup_metrics = channel.empty()
    ch_bcf         = channel.empty()
    ch_vcf         = channel.empty()
    ch_csv         = channel.empty()
    ch_consensus   = channel.empty()
    ch_dv_vcf      = channel.empty()
    ch_mutect_vcf  = channel.empty()

    // Parse each row, splitting it into reads and reference channels
    reads_ch = samplesheet_ch
        .splitCsv(header: true)
        .map { row ->tuple([id: row.sample, reference: row.reference], 
                    file(row.R1, checkIfExists: true), 
                    file(row.R2, checkIfExists: true))
       }

    // Every distinct reference the samplesheet asks for
    ref_ch = reads_ch
        .map { meta, _r1, _r2 -> meta.reference }
        .unique()

    // Index each reference if it is not already: reuse what sits next to the
    // fasta, otherwise build it once per reference. Both indexes are handled
    // the same way, so a bare .fasta is enough to run the pipeline.
    bwa_branch = ref_ch.branch { reference ->
        ready:   bwaIndexExists(reference_dir, reference)
        missing: true
    }
    BWA_INDEX(bwa_branch.missing.map { reference -> refFasta(reference_dir, reference) })

    // tuple(fasta name, tuple(fasta, index files)) - keyed so samples can join it
    bwa_index_ch = bwa_branch.ready
        .map { reference -> bwaIndexFor(reference_dir, reference) }
        .mix(BWA_INDEX.out.index)
        .map { fasta, index_files -> tuple(fasta.name, tuple(fasta, index_files)) }

    // The .fai is needed by coverage and by every variant caller
    fai_branch = ref_ch.branch { reference ->
        ready:   faidxExists(reference_dir, reference)
        missing: true
    }
    SAMTOOLS_FAIDX(
        fai_branch.missing.map { reference -> tuple([id: reference], refFasta(reference_dir, reference)) }
    )

    // tuple(fasta name, tuple(fasta, fai))
    faidx_ch = fai_branch.ready
        .map { reference -> faidxFor(reference_dir, reference) }
        .mix(SAMTOOLS_FAIDX.out.fai.map { meta, fai -> tuple(refFasta(reference_dir, meta.id), fai) })
        .map { fasta, fai -> tuple(fasta.name, tuple(fasta, fai)) }

    // Trim the reads
    if (params.trimmer == 'fastp') {
        FASTP_TRIM(reads_ch)
        trimmed_ch   = FASTP_TRIM.out.reads     // tuple(meta, r1, r2)
        ch_trim_html = FASTP_TRIM.out.html
        ch_trim_log  = FASTP_TRIM.out.log
    }
    else if (params.trimmer == 'cutadapt') {
        // TODO implement cutadapt
        // trimmed_ch = CUTADAPT.out.reads
        error "Cutadapt trimming not implemented yet."
    }

    // QC on the trimmed reads
    FASTQC_FASTQC(trimmed_ch)

    // One bundle per reference: the fasta with every sibling index file. The
    // aligners stage them together, which matters for Parabricks - it resolves
    // --ref to a real path and expects the whole index beside it, the .fai
    // included.
    ref_bundle_ch = bwa_index_ch
        .combine(faidx_ch, by: 0)
        .map { key, bwa, faidx -> tuple(key, tuple(bwa[0], bwa[1] + [faidx[1]])) }

    // Pair every sample with the reference bundle for its own reference
    aln_in = trimmed_ch
        .map { meta, r1, r2 -> tuple(refFasta(reference_dir, meta.reference).name, meta, r1, r2) }
        .combine(ref_bundle_ch, by: 0)
        .multiMap { _key, meta, r1, r2, index ->
            reads: tuple(meta, r1, r2)
            index: index
        }

    if (params.alignment.device == 'gpu'){
        PARABRICKS_FQ2BAM(aln_in.reads, aln_in.index)
        bam_ch         = PARABRICKS_FQ2BAM.out.bam     // tuple(meta, bam, bai)
        ch_dup_metrics = PARABRICKS_FQ2BAM.out.dup_metrics
    }
    else {
        BWA_MEM(aln_in.reads, aln_in.index)
        SAMTOOLS_INDEX(BWA_MEM.out.bam)
        bam_ch = SAMTOOLS_INDEX.out.bam     // tuple(meta, bam, bai)
    }

    // Alignment metrics
    SAMTOOLS_FLAGSTAT(bam_ch.map { meta, bam, _bai -> tuple(meta, bam) })

    // Create bigwig files
    bigwig_in = bam_ch
        .map { meta, bam, bai -> tuple(refFasta(reference_dir, meta.reference).name, meta, bam, bai) }
        .combine(faidx_ch, by: 0)
        .multiMap { _key, meta, bam, bai, faidx ->
            reads: tuple(meta, bam, bai)
            fasta: faidx
        }
    BEDTOOLS_BIGWIG(bigwig_in.reads, bigwig_in.fasta)  

    // Varian calling
    // bcftools
    if ('bcftools' in callers) {
        bcf_in = bam_ch
            .map { meta, bam, bai -> tuple(refFasta(reference_dir, meta.reference).name, meta, bam, bai) }
            .combine(faidx_ch, by: 0)
            .multiMap { _key, meta, bam, bai, faidx ->
                bam: tuple(meta, bam, bai)
                faidx: faidx
            }
        BCFTOOLS_CALL(bcf_in.bam, bcf_in.faidx)
        BCFTOOLS_VCF(BCFTOOLS_CALL.out.bcf)
        BCFTOOLS_CSV(BCFTOOLS_CALL.out.bcf)
        ch_bcf = BCFTOOLS_CALL.out.bcf
        ch_vcf = BCFTOOLS_VCF.out.vcf
        ch_csv = BCFTOOLS_CSV.out.csv
        
        cons_in = BCFTOOLS_CALL.out.bcf
            .map { meta, bcf, csi -> tuple(refFasta(reference_dir, meta.reference).name, meta, bcf, csi) }
            .combine(faidx_ch, by: 0)
            .multiMap { _key, meta, bcf, csi, faidx ->
                bcf:   tuple(meta, bcf, csi)
                faidx: faidx
            }
        BCFTOOLS_CONSENSUS(cons_in.bcf, cons_in.faidx)
        ch_consensus = BCFTOOLS_CONSENSUS.out.consensus
    }

    // deepvariant
    if ('deepvariant' in callers) {
        dv_in = bam_ch
            .map { meta, bam, bai -> tuple(refFasta(reference_dir, meta.reference).name, meta, bam, bai) }
            .combine(faidx_ch, by: 0)
            .multiMap { _key, meta, bam, bai, faidx ->
                bam: tuple(meta, bam, bai)
                faidx: faidx
            }
        PARABRICKS_DEEPVARIANT(dv_in.bam, dv_in.faidx)
        ch_dv_vcf = PARABRICKS_DEEPVARIANT.out.vcf
    }

    // mutect2
    if ('mutect2' in callers || 'mutect' in callers) {  
        mt_in = bam_ch
            .map { meta, bam, bai -> tuple(refFasta(reference_dir, meta.reference).name, meta, bam, bai) }
            .combine(faidx_ch, by: 0)
            .multiMap { _key, meta, bam, bai, faidx ->
                bam: tuple(meta, bam, bai)
                faidx: faidx
            }
        PARABRICKS_MUTECTCALLER(mt_in.bam, mt_in.faidx)
        ch_mutect_vcf = PARABRICKS_MUTECTCALLER.out.vcf
    }

    publish:
    samplesheet  = samplesheet_ch
    trimmed_html = ch_trim_html
    trimmed_log  = ch_trim_log
    fastqc_html  = FASTQC_FASTQC.out.html
    fastqc_zip   = FASTQC_FASTQC.out.zip
    flagstat     = SAMTOOLS_FLAGSTAT.out.flagstat
    alignment    = bam_ch
    dup_metrics  = ch_dup_metrics
    bigwig       = BEDTOOLS_BIGWIG.out.bigwig
    bcf          = ch_bcf
    vcf          = ch_vcf
    csv          = ch_csv
    consensus    = ch_consensus
    deepvariant  = ch_dv_vcf
    mutect       = ch_mutect_vcf
}

//
// Where each published output lands under the output directory
// (params.outdir, overridable with -output-dir / -o).
//
// Channels carrying tuple(meta, files...) are scanned recursively, so the meta
// map is ignored and every file in the tuple is published to the given path.
//
output {
    samplesheet  { path 'samplesheet'          }
    trimmed_html { path 'trimmed'              }
    trimmed_log  { path 'trimmed'              }
    fastqc_html  { path 'qc/fastqc'            }
    fastqc_zip   { path 'qc/fastqc'            }
    flagstat     { path 'qc/flagstat'          }
    alignment    { path 'alignment'            }
    dup_metrics  { path 'alignment'            }
    bigwig       { path 'bigwig'               }
    bcf          { path 'variants/bcf'         }
    vcf          { path 'variants/vcf'         }
    csv          { path 'variants/csv'         }
    consensus    { path 'consensus'            }
    deepvariant  { path 'variants/deepvariant' }
    mutect       { path 'variants/mutect'      }
}
