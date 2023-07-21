//
// Prepare reference indexing for downstream
//

include { FASTQ_ALIGN_BWAALN                                                                                                  } from '../../subworkflows/nf-core/fastq_align_bwaaln/main'
include { BWA_MEM                                                                                                             } from '../../modules/nf-core/bwa/mem/main'
include { BOWTIE2_ALIGN                                                                                                       } from '../../modules/nf-core/bowtie2/align/main'
include { SAMTOOLS_MERGE as SAMTOOLS_MERGE_LANES                                                                              } from '../../modules/nf-core/samtools/merge/main'
include { SAMTOOLS_SORT  as SAMTOOLS_SORT_MERGED_LANES                                                                        } from '../../modules/nf-core/samtools/sort/main'
include { SAMTOOLS_INDEX as SAMTOOLS_INDEX_MEM; SAMTOOLS_INDEX as SAMTOOLS_INDEX_BT2; SAMTOOLS_INDEX as SAMTOOLS_INDEX_MERGED_LANES } from '../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_FLAGSTAT as SAMTOOLS_FLAGSTAT_MAPPED                                                                       } from '../../modules/nf-core/samtools/flagstat/main'

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

    // Only run merge lanes if we have more than one BAM to merge!
    ch_input_for_lane_merge = ch_mapped_lane_bam
                                .map {
                                    meta, bam ->
                                    new_meta = meta.clone().findAll{ it.key !in ['lane', 'colour_chemistry'] }

                                    [ new_meta, bam ]
                                }
                                .groupTuple()
                                .branch {
                                    meta, bam ->
                                        println(bam.size())
                                        merge: bam.size() > 1
                                        skip: true
                                }

    SAMTOOLS_MERGE_LANES ( ch_input_for_lane_merge.merge, [], [] )
    ch_versions.mix( SAMTOOLS_MERGE_LANES.out.versions )

    // Then mix back merged and single lane libraries for everything downstream
    ch_mergedlanes_for_sorting = ch_input_for_lane_merge.skip
                                    .mix( SAMTOOLS_MERGE_LANES.out.bam )

    SAMTOOLS_SORT_MERGED_LANES ( ch_mergedlanes_for_sorting )
    ch_mapped_bam = SAMTOOLS_SORT_MERGED_LANES.out.bam
    ch_versions.mix( SAMTOOLS_SORT_MERGED_LANES.out.versions )

    SAMTOOLS_INDEX_MERGED_LANES( ch_mapped_bam )
    ch_mapped_bai =  params.fasta_largeref ? SAMTOOLS_INDEX_MERGED_LANES.out.csi : SAMTOOLS_INDEX_MERGED_LANES.out.bai
    ch_versions.mix( SAMTOOLS_INDEX_MERGED_LANES.out.versions )

    ch_input_for_flagstat = SAMTOOLS_SORT_MERGED_LANES.out.bam.join( SAMTOOLS_INDEX_MERGED_LANES.out.bai, failOnMismatch: true )

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
