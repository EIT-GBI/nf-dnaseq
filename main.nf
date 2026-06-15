#!/usr/bin/env nextflow

//
// Modules loaded from local dir
//
include {PREPARE_SAMPLESHEET} from './modules/samplesheet/prepare/main.nf'
include {TRIM} from './modules/fastp/trim/main.nf'
include {FASTQC} from './modules/fastqc/qc/main.nf'


//
// Modules loaded from nf-mod-repos
//


workflow {

    // Check if a samplesheet is provided, otherwise build one from the fastq directory and reference genome
    if (params.samplesheet) {
        samplesheet_ch = channel.fromPath(params.samplesheet)
    }
    else if (params.fastq_dir && params.reference_genome) {
        PREPARE_SAMPLESHEET(
            file("${projectDir}/" + params.scripts.py_samplesheet), 
            file(params.fastq_dir, checkIfExists: true), 
            file(params.reference_genome, checkIfExists: true)
            )
        samplesheet_ch = PREPARE_SAMPLESHEET.out.csv
    }
    else {
        error "You must provide either a samplesheet or a fastq directory and reference genome."
    }

    // Parse each row, splitting it into reads and reference channels
    inputs = samplesheet_ch
        .splitCsv(header: true)
        .multiMap { row ->
        reads:  tuple(row.sample, 
                file(row.R1, checkIfExists: true), 
                file(row.R2, checkIfExists: true))
        reference: tuple(row.sample,
                file(row.reference, checkIfExists: true))   
        }
    
    reads_ch = inputs.reads
    reference_ch = inputs.reference.unique()

    // TODO Check to see if all references needed are indexed, if not index them

    // Now trim the reads
    TRIM(reads_ch)
    trimmed_ch = TRIM.out.reads

    // QC on the trimmed reads
    FASTQC(trimmed_ch)

}