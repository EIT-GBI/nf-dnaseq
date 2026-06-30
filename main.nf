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
include {PARABRICKS_DEEPVARIANT} from './modules/parabricks/deepvariant/main.nf'
include {PARABRICKS_MUTECTCALLER} from './modules/parabricks/mutectcaller/main.nf'
include {BEDTOOLS_BIGWIG} from './modules/bedtools/bigwig/main.nf'
include {BCFTOOLS_CONSENSUS} from './modules/bcftools/consensus/main.nf'
include {BCFTOOLS_CALL} from './modules/bcftools/call/main.nf'
include {BCFTOOLS_CSV} from './modules/bcftools/csv/main.nf'
include {BCFTOOLS_VCF} from './modules/bcftools/vcf/main.nf'
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

    // Create bigwig files
    bigwig_in = bam_ch.multiMap { meta, bam, bai ->
        reads: tuple(meta, bam, bai)
        fasta: faidxFor(meta)
    }
    BEDTOOLS_BIGWIG(bigwig_in.reads, bigwig_in.fasta)  

    // Varian calling
    // bcftools
    if ('bcftools' in callers) {
        bcf_in = bam_ch.multiMap { meta, bam, bai ->
            bam: tuple(meta, bam, bai)
            faidx: faidxFor(meta)
        }
        BCFTOOLS_CALL(bcf_in.bam, bcf_in.faidx)
        BCFTOOLS_VCF(BCFTOOLS_CALL.out.bcf)
        BCFTOOLS_CSV(BCFTOOLS_CALL.out.bcf)
        
        cons_in = BCFTOOLS_CALL.out.bcf.multiMap { meta, bcf, csi ->
            bcf:   tuple(meta, bcf, csi)
            faidx: faidxFor(meta)
        }
        BCFTOOLS_CONSENSUS(cons_in.bcf, cons_in.faidx)

    }

    // deepvariant
    if ('deepvariant' in callers) {
        dv_in = bam_ch.multiMap { meta, bam, bai ->
            bam: tuple(meta, bam, bai)
            faidx: faidxFor(meta)
        }
        PARABRICKS_DEEPVARIANT(dv_in.bam, dv_in.faidx)
    }

    // mutect2
    if ('mutect2' in callers || 'mutect' in callers) {  
        mt_in = bam_ch.multiMap { meta, bam, bai ->
            bam: tuple(meta, bam, bai)
            faidx: faidxFor(meta)
        }
        PARABRICKS_MUTECTCALLER(mt_in.bam, mt_in.faidx)
    }


}