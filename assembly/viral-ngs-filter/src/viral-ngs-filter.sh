#!/bin/bash

main() {
    set -e -x -o pipefail

    # stage the inputs
    pids=()
    dx cat "$resources" | pigz -dc | tar x -C / & pids+=($!)
    dx download "$targets" -o targets.fasta & pids+=($!)
    dx download "$reads" -o reads.bam
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    # build Lastal target database to working dir with prefix targets.db
    # taxon_filter.py lastal_build_db [input_fasta] [output_dir] [output_prefix]
    viral-ngs taxon_filter.py lastal_build_db /user-data/targets.fasta /user-data --outputFilePrefix targets.db
    ls
    sha256sum targets.*

    # filter the reads
    viral-ngs taxon_filter.py filter_lastal_bam /user-data/reads.bam /user-data/targets.db /user-data/filtered_reads.bam

    prefiltration_read_count=$(samtools view -c reads.bam)
    prefiltration_base_count=$(bam_base_count reads.bam)

    filtered_read_count=$(samtools view -c filtered_reads.bam)
    filtered_base_count=$(bam_base_count filtered_reads.bam)

    dx-jobutil-add-output prefiltration_read_count $prefiltration_read_count
    dx-jobutil-add-output prefiltration_base_count $prefiltration_base_count
    dx-jobutil-add-output filtered_read_count $filtered_read_count
    dx-jobutil-add-output filtered_base_count $filtered_base_count
    dxid=$(dx upload --brief --destination "${reads_prefix}.filtered.bam" filtered_reads.bam)
    dx-jobutil-add-output filtered_reads --class=file "$dxid"
}

bam_base_count() {
    samtools view $1 | cut -f10 | tr -d '\n' | wc -c
}
