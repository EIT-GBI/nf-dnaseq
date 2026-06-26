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
include {BWA_MEM} from './modules/bwa/mem/main.nf'
include {SAMTOOLS_INDEX} from './modules/samtools/index/main.nf'
include {SAMTOOLS_FLAGSTAT} from './modules/samtools/flagstat/main.nf'
include {PARABRICKS_FQ2BAM} from './modules/parabricks/fq2bam/main.nf'
include {BEDTOOLS_BIGWIG} from './modules/bedtools/bigwig/main.nf'
include {refFasta; bwaIndexFor; faidxFor} from './modules/utils/references.nf'




workflow {

    // Some basic checks on the input parameters
    if (!(params.alignment.device in ['cpu', 'gpu'])){
        error "Invalid value for params.alignment.device: ${params.alignment.device}. Use 'cpu' for bwa+samtools or 'gpu' for Parabricks."
    }

    if (!(params.trimmer in ['fastp', 'cutadapt'])){
        error "Invalid value for params.trimmer: ${params.trimmer}. Use 'fastp' or 'cutadapt'."
    }

    // Check if a samplesheet is provided, otherwise build one from the fastq directory and reference genome
    if (params.samplesheet) {
        samplesheet_ch = channel.fromPath(params.samplesheet, checkIfExists: true)
    }
    else if (params.fastq_dir && params.reference_genome) {
        PREPARE_SAMPLESHEET(
            file("${projectDir}/" + params.scripts.py_samplesheet), 
            file(params.fastq_dir, checkIfExists: true), 
            params.reference_genome
            )
        samplesheet_ch = PREPARE_SAMPLESHEET.out.csv
    }
    else {
        error "You must provide either a samplesheet or a fastq directory and reference genome."
    }


    // Parse each row, splitting it into reads and reference channels
    reads_ch = samplesheet_ch
        .splitCsv(header: true)
        .map { row ->tuple([id: row.sample, reference: row.reference], 
                    file(row.R1, checkIfExists: true), 
                    file(row.R2, checkIfExists: true))
       }
    
    // TODO Check to see if all references needed are indexed, if not index them

    // Trim the reads
    if (params.trimmer == 'fastp') {
        FASTP_TRIM(reads_ch)
        trimmed_ch = FASTP_TRIM.out.reads     // tuple(meta, r1, r2)
    }
    else if (params.trimmer == 'cutadapt') {
        // TODO implement cutadapt
        // trimmed_ch = CUTADAPT.out.reads
        error "Cutadapt trimming not implemented yet."
    }

    // QC on the trimmed reads
    FASTQC_FASTQC(trimmed_ch)

    // Create an alignment channel with the trimmed reads and the reference files
    aln_in = trimmed_ch.multiMap { meta, r1, r2 ->
        reads: tuple(meta, r1, r2)
        index: bwaIndexFor(meta)   
    }

    if (params.alignment.device == 'gpu'){
        PARABRICKS_FQ2BAM(aln_in.reads, aln_in.index)
        bam_ch = PARABRICKS_FQ2BAM.out.bam     // tuple(meta, bam, bai)
    }
    else {
        BWA_MEM(aln_in.reads, aln_in.index)
        SAMTOOLS_INDEX(BWA_MEM.out.bam)
        bam_ch = SAMTOOLS_INDEX.out.bam     // tuple(meta, bam, bai)
    }

    // Alignment metrics
    SAMTOOLS_FLAGSTAT(bam_ch.map { meta, bam, bai -> tuple(meta, bam) })

    


}