#!/bin/bash

samtools=/home/dnanexus/viral-ngs/tools/conda-tools/default/bin/samtools

main() {
    set -e -x -o pipefail
    export PATH="$PATH:$HOME/miniconda/bin"

    # stage the inputs
    pids=()
    dx cat "$resources" | zcat | tar x -C / & pids+=($!)
    dx download "$targets" -o targets.fasta & pids+=($!)
    dx download "$reads" -o reads.bam
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    # build Lastal target database to working dir with prefix targets.db
    # taxon_filter.py lastal_build_db [input_fasta] [output_dir] [output_prefix]
    python viral-ngs/taxon_filter.py lastal_build_db targets.fasta ./ --outputFilePrefix targets.db
    ls
    sha256sum targets.*

    # filter the reads
    python viral-ngs/taxon_filter.py filter_lastal_bam reads.bam targets.db filtered_reads.bam


    dx-jobutil-add-output prefiltration_read_count $($samtools view -c reads.bam)
    dx-jobutil-add-output prefiltration_base_count $(bam_base_count reads.bam)
    dx-jobutil-add-output filtered_read_count $($samtools view -c filtered_reads.bam)
    dx-jobutil-add-output filtered_base_count $(bam_base_count filtered_reads.bam)
    dx-jobutil-add-output filtered_reads --class=file \
        $(dx upload --brief --destination "${reads_prefix}.filtered.bam" filtered_reads.bam)
}

bam_base_count() {
    $samtools view $1 | cut -f10 | tr -d '\n' | wc -c
}
