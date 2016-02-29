#!/bin/bash

samtools=viral-ngs/tools/build/conda-tools/bin/samtools

main() {
    set -e -x -o pipefail
    export PATH="$PATH:$HOME/miniconda/bin"

    # stage the inputs
    pids=()
    dx cat "$resources" | zcat | tar x -C / & pids+=($!)
    dx download "$reads" -o reads.bam & pids+=($!)
    dx download "$contaminants" -o contaminants.fasta
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    # check min_base_count
    filtered_base_count=$(bam_base_count reads.bam)
    if [ "$filtered_base_count" -lt "$min_base_count" ]; then
        dx-jobutil-report-error "Too few bases survived filtering (${filtered_base_count} < ${min_base_count})" AppError
        exit 1
    fi

    # run trinity
    ulimit -s unlimited
    python viral-ngs/assembly.py assemble_trinity reads.bam contaminants.fasta assembly.fasta --n_reads=$subsample --outReads subsamp.bam

    # collect figures of merit
    subsampled_read_pair_count=$(expr $($samtools view -c subsamp.bam) / 2)
    subsampled_base_count=$($samtools view subsamp.bam | cut -f10 | tr -d '\n' | wc -c)

    # output
    dx-jobutil-add-output subsampled_reads --class=file \
            $(dx upload --brief --destination "${reads_prefix}.trimmed_subsample.bam" subsamp.bam)
    dx-jobutil-add-output subsampled_read_pair_count --class=int $subsampled_read_pair_count
    dx-jobutil-add-output subsampled_base_count --class=int $subsampled_base_count
    dx-jobutil-add-output contigs --class=file \
            $(dx upload --brief --destination "${reads_prefix}.trinity.fasta" assembly.fasta)
}

bam_base_count() {
    $samtools view $1 | cut -f10 | tr -d '\n' | wc -c
}
