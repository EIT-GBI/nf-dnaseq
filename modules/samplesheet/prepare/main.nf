// Build a samplesheet from a directory of fastq files and a reference genome

process PREPARE_SAMPLESHEET {
    tag "${input_dir}"

    publishDir "${params.outdir}/samplesheet", mode: 'copy'

    input:
    path pyscript
    path input_dir
    val reference

    output:
    path "samplesheet.csv", emit: csv

    script:
    """
    python3 ${pyscript} \\
        --input_dir ${input_dir} \\
        --reference ${reference} \\
        --output samplesheet.csv
    """
    
    stub:
    """
    touch samplesheet.csv
    """
}