#!/usr/bin/env nextflow

//
// Modules loaded from local dir
//
include {PREPARE_SAMPLESHEET} from './modules/samplesheet/prepare/main.nf'


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

}