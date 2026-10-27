// Fixture for tests/pipefail.nf.test: a pipe shaped like BWA_MEM's
// `bwa mem | samtools sort > out.bam`, where the upstream command writes some
// output then fails and the downstream command succeeds and writes a file.
//
// Run as a pipeline rather than an nf-test process test: nf-test 0.9.3 wraps
// processes in a `PROCESS(*input)` call that Nextflow's strict syntax rejects.
process PIPE_UPSTREAM_FAILS {

    output:
    path 'partial.txt'

    script:
    """
    (printf 'partial\\n'; exit 1) | cat > partial.txt
    """
}

workflow {
    PIPE_UPSTREAM_FAILS()
}
