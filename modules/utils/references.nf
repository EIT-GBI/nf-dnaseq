// Helpers for parsing the right reference files

// Get the reference fasta file for a given sample
def refFasta(meta) {
    file("${params.reference_dir}/${meta.reference}", checkIfExists: true)
}

// Get the bwa index files for a given sample
def bwaIndexFor(meta) {
    def fasta = refFasta(meta)
    tuple(fasta, ['amb', 'ann', 'bwt', 'pac', 'sa'].collect { ext -> file("${fasta}.${ext}", checkIfExists: true) })
}

def faidxFor(meta) {
    def fasta = refFasta(meta)
    tuple(fasta, file("${fasta}.fai", checkIfExists: true))
}

