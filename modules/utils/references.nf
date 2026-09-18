// Helpers for resolving reference files.
//
// These take the reference directory explicitly rather than reading
// params.reference_dir: params are intended for the entry workflow and the
// output block only, so helper code stays usable from anywhere.
//
// Sibling files (.fai, .amb, ...) are built from the URI *string*, not from a
// resolved file object: stringifying a remote file drops its scheme and host,
// which would silently turn an https reference into a bogus local path.

// Extensions written by `bwa index`
def bwaIndexExtensions() {
    ['amb', 'ann', 'bwt', 'pac', 'sa']
}

// Location of the reference fasta, as a string (may be a local path or a URL)
def refUri(reference_dir, reference) {
    "${reference_dir}/${reference}"
}

// Resolve the reference fasta for a samplesheet 'reference' entry
def refFasta(reference_dir, reference) {
    file(refUri(reference_dir, reference), checkIfExists: true)
}

// True when every bwa index file sits next to the fasta already
def bwaIndexExists(reference_dir, reference) {
    def uri = refUri(reference_dir, reference)
    bwaIndexExtensions().every { ext -> file("${uri}.${ext}").exists() }
}

// tuple(fasta, [index files]) for a reference that is already indexed
def bwaIndexFor(reference_dir, reference) {
    def uri = refUri(reference_dir, reference)
    tuple(
        file(uri, checkIfExists: true),
        bwaIndexExtensions().collect { ext -> file("${uri}.${ext}", checkIfExists: true) }
    )
}

// True when a samtools .fai already sits next to the fasta
def faidxExists(reference_dir, reference) {
    file("${refUri(reference_dir, reference)}.fai").exists()
}

// tuple(fasta, fai) for a reference that already has a .fai
def faidxFor(reference_dir, reference) {
    def uri = refUri(reference_dir, reference)
    tuple(
        file(uri, checkIfExists: true),
        file("${uri}.fai", checkIfExists: true)
    )
}
