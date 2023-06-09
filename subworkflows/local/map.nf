//
// Prepare reference indexing for downstream
//

include { FASTQ_ALIGN_BWAALN                                                                                                 } from '../../subworkflows/nf-core/fastq_align_bwaaln/main'
include { BWA_MEM                                                                                                            } from '../../modules/nf-core/bwa/mem/main'
include { BOWTIE2_ALIGN                                                                                                      } from '../../modules/nf-core/bowtie2/align/main'
include { SAMTOOLS_MERGE                                                                                                     } from '../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_SORT                                                                                                      } from '../../modules/nf-core/samtools/sort/main'
include { SAMTOOLS_INDEX as SAMTOOLS_INDEX_MEM; SAMTOOLS_INDEX as SAMTOOLS_INDEX_BT2; SAMTOOLS_INDEX as SAMTOOLS_INDEX_MERGE } from '../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_FLAGSTAT as SAMTOOLS_FLAGSTAT_MAPPED                                                                      } from '../../modules/nf-core/samtools/flagstat/main'

workflow MAP {
    take:
    reads // [ [meta], [read1, reads2] ] or [ [meta], [read1] ]
    index // [ [meta], [ index ] ]

    main:
    ch_versions       = Channel.empty()
    ch_multiqc_files  = Channel.empty()

    ch_input_for_mapping = reads
                            .combine(index)
                            .multiMap {
                                meta, reads, meta2, index ->
                                    new_meta = meta.clone()
                                    new_meta.reference = meta2.id
                                    reads: [ new_meta, reads ]
                                    index: [ meta2, index]
                            }

    if ( params.mapping_tool == 'bwaaln' ) {
        FASTQ_ALIGN_BWAALN ( ch_input_for_mapping.reads, ch_input_for_mapping.index )

        ch_versions        = ch_versions.mix ( FASTQ_ALIGN_BWAALN.out.versions.first() )
        ch_mapped_lane_bam = FASTQ_ALIGN_BWAALN.out.bam
        ch_mapped_lane_bai = params.fasta_largeref ? FASTQ_ALIGN_BWAALN.out.csi : FASTQ_ALIGN_BWAALN.out.bai

    } else if ( params.mapping_tool == 'bwamem' ) {
        BWA_MEM ( ch_input_for_mapping.reads, ch_input_for_mapping.index, true )
        ch_versions        = ch_versions.mix ( BWA_MEM.out.versions.first() )
        ch_mapped_lane_bam = BWA_MEM.out.bam

        SAMTOOLS_INDEX_MEM ( ch_mapped_lane_bam )
        ch_versions        = ch_versions.mix(SAMTOOLS_INDEX_MEM.out.versions.first())
        ch_mapped_lane_bai = params.fasta_largeref ? SAMTOOLS_INDEX_MEM.out.csi : SAMTOOLS_INDEX_MEM.out.bai

    } else if ( params.mapping_tool == 'bowtie2' ) {
        BOWTIE2_ALIGN ( ch_input_for_mapping.reads, ch_input_for_mapping.index, false, true )
        ch_versions        = ch_versions.mix ( BOWTIE2_ALIGN.out.versions.first() )
        ch_mapped_lane_bam = BOWTIE2_ALIGN.out.bam

        SAMTOOLS_INDEX_BT2 ( ch_mapped_lane_bam )
        ch_versions        = ch_versions.mix(SAMTOOLS_INDEX_BT2.out.versions.first())
        ch_mapped_lane_bai = params.fasta_largeref ? SAMTOOLS_INDEX_BT2.out.csi : SAMTOOLS_INDEX_BT2.out.bai
    }

    ch_input_for_lane_merge = ch_mapped_lane_bam
                                .map {
                                    meta, bam ->
                                    new_meta = meta.clone().findAll{ it.key !in ['lane', 'colour_chemistry'] }

                                    [ new_meta, bam ]
                                }
                                .groupTuple()

    SAMTOOLS_MERGE ( ch_input_for_lane_merge, [], [] )
    ch_versions.mix( SAMTOOLS_MERGE.out.versions )

    SAMTOOLS_SORT ( SAMTOOLS_MERGE.out.bam )
    ch_mapped_bam = SAMTOOLS_SORT.out.bam
    ch_versions.mix( SAMTOOLS_SORT.out.versions )

    SAMTOOLS_INDEX_MERGE( ch_mapped_bam )
    ch_mapped_bai =  params.fasta_largeref ? SAMTOOLS_INDEX_MERGE.out.csi : SAMTOOLS_INDEX_MERGE.out.bai
    ch_versions.mix( SAMTOOLS_INDEX_MERGE.out.versions )

    ch_input_for_flagstat = SAMTOOLS_SORT.out.bam.join( SAMTOOLS_INDEX_MERGE.out.bai, failOnMismatch: true )

    SAMTOOLS_FLAGSTAT_MAPPED ( ch_input_for_flagstat )
    ch_versions.mix( SAMTOOLS_FLAGSTAT_MAPPED.out.versions.first() )
    ch_multiqc_files = ch_multiqc_files.mix( SAMTOOLS_FLAGSTAT_MAPPED.out.flagstat )

    emit:
    bam        = ch_mapped_bam                            // [ [ meta ], bam ]
    bai        = ch_mapped_bai                            // [ [ meta ], bai ]
    flagstat   = SAMTOOLS_FLAGSTAT_MAPPED.out.flagstat    // [ [ meta ], stats ]
    mqc        = ch_multiqc_files
    versions   = ch_versions

}
