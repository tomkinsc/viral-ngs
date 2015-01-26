#!/bin/bash

samtools=viral-ngs/tools/build/samtools-0.1.19/samtools

main() {
    set -e -x -o pipefail

    # stage the inputs
    pids=()
    dx cat "$resources" | zcat | tar x -C / & pids+=($!)
    dx download "$targets" -o targets.fasta & pids+=($!)
    dx download "$reads" -o reads.bam
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    # build Lastal target database
    viral-ngs/tools/build/last-490/bin/lastdb -c targets.db targets.fasta
    sha256sum targets.*

    # filter the reads
    python viral-ngs/taxon_filter.py filter_lastal_bam reads.bam targets.db filtered_reads.bam

    # check min_base_count
    filtered_base_count=$(bam_base_count filtered_reads.bam)
    if [ "$filtered_base_count" -lt "$min_base_count" ]; then
        dx-jobutil-report-error "Too few bases survived filtering (${filtered_base_count} < ${min_base_count})" AppError
        exit 1
    fi

    dx-jobutil-add-output unfiltered_read_count $($samtools view -c reads.bam)
    dx-jobutil-add-output unfiltered_base_count $(bam_base_count reads.bam)
    dx-jobutil-add-output filtered_read_count $($samtools view -c filtered_reads.bam)
    dx-jobutil-add-output filtered_base_count $filtered_base_count
    dx-jobutil-add-output filtered_reads --class=file \
        $(dx upload --brief --destination "${reads_prefix}.filtered.bam" filtered_reads.bam)
}

bam_base_count() {
    $samtools view $1 | cut -f10 | tr -d '\n' | wc -c
}
