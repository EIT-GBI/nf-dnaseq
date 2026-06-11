#!/usr/bin/env nextflow

//
// Modules loaded from local dir
//
include {PREPARE_SAMPLESHEET} from './modules/samplesheet/prepare/main.nf'


//
// Modules loaded from nf-mod-repos
//


workflow {

    if (params.samplesheet) {
        samplesheet_ch = channel.fromPath(params.samplesheet)
    }
    else if (params.fastq_dir && params.reference_genome) {
        samplesheet_ch = PREPARE_SAMPLESHEET(params.scripts.py_samplesheet, params.fastq_dir, params.reference_genome)
    }
    else {
        error "You must provide either a samplesheet or a fastq directory and reference genome."
    }

}