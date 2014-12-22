#!/bin/bash

main() {
    set -e -x -o pipefail

    # stage the inputs
    dx cat "$resources" | zcat | tar x -C / &
    dx download "$reference" -o reference.fasta &
    dx cat "$reads" | zcat > reads.fastq &
    dx cat "$reads2" | zcat > reads2.fastq
    wait

    # build Lastal reference database
    viral-ngs/tools/build/last-490/bin/lastdb -c reference.db reference.fasta

    # filter & dedup the reads
    python viral-ngs/taxon_filter.py filter_lastal reads.fastq reference.db filtered_reads.pre.fastq &
    python viral-ngs/taxon_filter.py filter_lastal reads2.fastq reference.db filtered_reads2.pre.fastq
    wait

    wc -l filtered_reads.pre.fastq
    wc -l filtered_reads2.pre.fastq

    # purge unmated reads
    cmd='python viral-ngs/read_utils.py purge_unmated filtered_reads.pre.fastq filtered_reads2.pre.fastq filtered_reads.fastq filtered_reads2.fastq'
    if [ -n "$read_id_regex" ]; then
        $cmd --regex "$read_id_regex"
    else
        $cmd
    fi

    wc -l filtered_reads.fastq
    wc -l filtered_reads2.fastq

    # upload filtered reads
    dx-jobutil-add-output filtered_reads --class=file \
        $(gzip -c filtered_reads.fastq | dx upload --brief --destination "${reads_prefix}.filtered.fastq.gz" -)
    dx-jobutil-add-output filtered_reads2 --class=file \
        $(gzip -c filtered_reads2.fastq | dx upload --brief --destination "${reads2_prefix}.filtered.fastq.gz" -)
}
