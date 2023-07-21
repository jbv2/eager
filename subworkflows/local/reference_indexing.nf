//
// Prepare reference indexing for downstream
//

include { REFERENCE_INDEXING_SINGLE } from '../../subworkflows/local/reference_indexing_single.nf'
//include { REFERENCE_INDEXING_MULTI  } from '../../subworkflows/local/reference_indexing_multi.nf'

workflow REFERENCE_INDEXING {
    take:
    fasta // file: /path/to/samplesheet.csv
    fasta_fai
    fasta_dict
    fasta_mapperindexdir

    main:
    ch_versions = Channel.empty()

    // TODO add WARN: if fasta.ext == csv && fai/dict/mapperindexdir supplied, then latter will be ignored with preference for info in csv!

    if ( fasta_fai && fasta_dict && fasta_mapperindexdir ) {
        // TODO: if all are supplied
    } else if ( fasta.extension == 'csv' | fasta.extension == 'tsv' ) {
        ch_reference_for_mapping = REFERENCE_INDEXING_MULTI ( fasta ).reference
        ch_versions = ch_versions.mix( REFERENCE_INDEXING_MULTI.out.versions )
    } else {
        ch_reference_for_mapping = REFERENCE_INDEXING_SINGLE ( fasta, fasta_fai, fasta_dict, fasta_mapperindexdir ).reference
        ch_versions = ch_versions.mix( REFERENCE_INDEXING_SINGLE.out.versions )
    }

    emit:
    reference = ch_reference_for_mapping // [ meta, fasta, fai, dict, mapindex ]
    versions  = ch_versions

}
