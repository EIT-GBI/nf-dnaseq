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

// ---------------------------------------------------------------------------
// Normalising a reference to a plain, uncompressed fasta
// ---------------------------------------------------------------------------
//
// A samplesheet may name a bgzipped reference (`genome.fa.gz`), but the tools
// downstream do not agree on what they can read:
//
//   bwa       reads bgzip fine
//   bcftools  needs a .gzi beside the .fai
//   bedtools  only ever touches the .fai
//   pbrun     cannot read it at all - it parses the fasta itself, sees only
//             part of the contigs and then reports the rest as missing from
//             the reference, long after alignment has succeeded
//
// So the reference is normalised once, here, before anything indexes or reads
// it: every consumer is handed one plain fasta, and no process ever receives a
// .gz. Each reference is decompressed at most once per cluster - the result is
// published back next to the original, where the next run's existence checks
// find it.

// True when the samplesheet entry names a gzipped fasta
def isGzipped(reference) {
    "${reference}".endsWith('.gz')
}

// The reference as every tool downstream sees it: the uncompressed fasta
def plainRef(reference) {
    isGzipped(reference) ? "${reference}"[0..-4] : "${reference}"
}

// The key samples and reference bundles are joined on. Derived from the
// samplesheet *string*, never from a file object: the plain fasta may not
// exist on disk yet when the key is first needed.
def refKey(reference) {
    plainRef(reference).tokenize('/')[-1]
}

// True when this reference still has to be decompressed. A gzipped reference
// whose plain fasta already sits beside it - published by an earlier run, or
// put there by hand - is used directly.
def needsDecompression(reference_dir, reference) {
    isGzipped(reference) && !file(refUri(reference_dir, plainRef(reference))).exists()
}

// Directory holding this reference, for publishing siblings back next to it
def refParentDir(reference_dir, reference) {
    def rel = "${reference}"
    def cut = rel.lastIndexOf('/')
    cut > 0 ? "${reference_dir}/${rel.substring(0, cut)}" : "${reference_dir}"
}

process DECOMPRESS_REFERENCE {
    tag "${gz.name}"

    // Published next to the original, so later runs - and other pipelines on
    // the same cluster - skip this step entirely. A read-only or remote
    // reference_dir is not fatal: the run itself uses the work dir copy.
    publishDir path: { refParentDir(params.reference_dir, reference) }, mode: 'copy', overwrite: false,
               failOnError: false, enabled: !"${params.reference_dir}".contains('://')

    input:
    tuple val(reference), path(gz)

    output:
    tuple val(reference), path("${gz.baseName}"), emit: fasta

    script:
    """
    gzip -cd ${gz} > ${gz.baseName}
    """

    stub:
    """
    touch ${gz.baseName}
    """
}
