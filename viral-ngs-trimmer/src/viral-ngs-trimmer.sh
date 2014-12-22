#!/bin/bash

main() {
    set -e -x -o pipefail

    dx cat "$resources" | zcat | tar x -C / &
    dx cat "$reads" | zcat > reads.fa &
    dx cat "$reads2" | zcat > reads2.fa &
    dx download "$adapters_etc" -o adapters_etc.fasta
    wait

    python viral-ngs/taxon_filter.py trim_trimmomatic reads.fa reads2.fa trimmed_reads.fa trimmed_reads2.fa adapters_etc.fasta

    trimmed_reads=$(gzip -c trimmed_reads.fa | dx upload --brief -o "${reads_prefix}.trimmed.fastq.gz" -)
    dx-jobutil-add-output trimmed_reads "$trimmed_reads" --class=file
    trimmed_reads2=$(gzip -c trimmed_reads2.fa | dx upload --brief -o "${reads2_prefix}.trimmed.fastq.gz" -)
    dx-jobutil-add-output trimmed_reads2 "$trimmed_reads2" --class=file
}
