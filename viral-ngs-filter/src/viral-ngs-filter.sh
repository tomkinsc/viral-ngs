#!/bin/bash

main() {
    set -e -x -o pipefail

    # stage the inputs
    pids=()
    dx cat "$resources" | zcat | tar x -C / & pids+=($!)
    dx download "$targets" -o targets.fasta & pids+=($!)
    dx download "$reads" -o reads.bam
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    # Stash the PYTHONPATH used by dx
    DX_PYTHONPATH=$PYTHONPATH
    DX_PATH=$PATH

    # Load viral-ngs virtual environment
    # Disable error propagation for now (there are warning :/ )
    unset PYTHONPATH

    set +e +o pipefail
    source easy-deploy-viral-ngs.sh load

    # build Lastal target database to working dir with prefix targets.db
    # taxon_filter.py lastal_build_db [input_fasta] [output_dir] [output_prefix]
    taxon_filter.py lastal_build_db targets.fasta ./ --outputFilePrefix targets.db
    ls
    sha256sum targets.*

    # filter the reads
    taxon_filter.py filter_lastal_bam reads.bam targets.db filtered_reads.bam

    prefiltration_read_count=$(samtools view -c reads.bam)
    prefiltration_base_count=$(bam_base_count reads.bam)

    filtered_read_count=$(samtools view -c filtered_reads.bam)
    filtered_base_count=$(bam_base_count filtered_reads.bam)

    # deactivate viral-ngs virtual environment
    source deactivate

    # restore paths from DX
    export PYTHONPATH=$DX_PYTHONPATH
    export PATH=$DX_PATH

    set -x -o pipefail

    dx-jobutil-add-output prefiltration_read_count $prefiltration_read_count
    dx-jobutil-add-output prefiltration_base_count $prefiltration_base_count
    dx-jobutil-add-output filtered_read_count $filtered_read_count
    dx-jobutil-add-output filtered_base_count $filtered_base_count
    dx-jobutil-add-output filtered_reads --class=file \
        $(dx upload --brief --destination "${reads_prefix}.filtered.bam" filtered_reads.bam)
}

bam_base_count() {
    samtools view $1 | cut -f10 | tr -d '\n' | wc -c
}
