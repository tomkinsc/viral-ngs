#!/bin/bash

main() {
    set -e -x -o pipefail

    # stage the inputs
    dx cat "$resources" | zcat | tar x -C / &
    dx download "$targets" -o targets.fasta &
    dx cat "$reads" | zcat > reads.fastq &
    dx cat "$reads2" | zcat > reads2.fastq
    wait

    # build Lastal target database
    viral-ngs/tools/build/last-490/bin/lastdb -c targets.db targets.fasta

    # filter & dedup the reads
    python viral-ngs/taxon_filter.py filter_lastal reads.fastq targets.db filtered_reads.pre.fastq &
    python viral-ngs/taxon_filter.py filter_lastal reads2.fastq targets.db filtered_reads2.pre.fastq
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

    dx_filtered_reads=$(gzip -c filtered_reads.fastq | dx upload --brief --destination "${reads_prefix}.filtered.fastq.gz" -)
    dx-jobutil-add-output filtered_reads --class=file "$dx_filtered_reads"
    dx_filtered_reads2=$(gzip -c filtered_reads2.fastq | dx upload --brief --destination "${reads2_prefix}.filtered.fastq.gz" -)
    dx-jobutil-add-output filtered_reads2 --class=file "$dx_filtered_reads2"

    # subsample the read pairs if desired
    if [ "$subsample" -gt 0 ]; then
        python viral-ngs/tools/scripts/subsampler.py -n "$subsample" -mode p -in filtered_reads.fastq filtered_reads2.fastq -out filtered_reads.subsample.fastq filtered_reads2.subsample.fastq
        wc -l filtered_reads.subsample.fastq
        wc -l filtered_reads2.subsample.fastq
        dx-jobutil-add-output filtered_subsampled_reads --class=file \
            $(gzip -c filtered_reads.subsample.fastq | dx upload --brief --destination "${reads_prefix}.filtered.subsampled.fastq.gz" -)
        dx-jobutil-add-output filtered_subsampled_reads2 --class=file \
            $(gzip -c filtered_reads2.subsample.fastq | dx upload --brief --destination "${reads2_prefix}.filtered.subsampled.fastq.gz" -)
    else
        dx-jobutil-add-output filtered_subsampled_reads --class=file "$dx_filtered_reads"
        dx-jobutil-add-output filtered_subsampled_reads2 --class=file "$dx_filtered_reads2"
    fi
}
