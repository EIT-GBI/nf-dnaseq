// Build a samplesheet from a directory of fastq files and a reference genome

process PREPARE_SAMPLESHEET {
    tag "${input_dir}"

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
    # An empty file is not enough here: the workflow feeds this straight into
    # splitCsv(header: true), which throws "Missing 'header' in CSV file". Emit
    # a real samplesheet, pairing files the same way generate_samplesheet.py
    # does, so a -stub-run exercises the rest of the workflow rather than
    # stopping at the first operator.
    echo "sample,R1,R2,reference" > samplesheet.csv
    for r1 in ${input_dir}/*_R1*.fastq.gz ${input_dir}/*_R1*.fq.gz ${input_dir}/*_R1*.fastq ${input_dir}/*_R1*.fq; do
        [ -e "\$r1" ] || continue
        r2=\$(echo "\$r1" | sed 's/_R1/_R2/')
        [ -e "\$r2" ] || continue
        sample=\$(basename "\$r1" | sed 's/_R1.*//')
        echo "\$sample,\$(readlink -f "\$r1"),\$(readlink -f "\$r2"),${reference}" >> samplesheet.csv
    done
    """
}