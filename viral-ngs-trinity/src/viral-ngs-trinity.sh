#!/bin/bash

main() {
    set -e -x -o pipefail

    # stage the inputs
    pids=()
    dx cat "$resources" | zcat | tar x -C / & pids+=($!)
    dx download "$reads" -o reads.bam & pids+=($!)
    dx download "$contaminants" -o contaminants.fasta
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    # run trinity
    ulimit -s unlimited
    python viral-ngs/assembly.py assemble_trinity reads.bam contaminants.fasta assembly.fasta --n_reads=$subsample --outReads subsamp.bam

    # collect figures of merit
    subsampled_read_pair_count=$(expr $(viral-ngs/tools/build/samtools-0.1.19/samtools view -c subsamp.bam) / 2)
    subsampled_base_count=$(viral-ngs/tools/build/samtools-0.1.19/samtools view subsamp.bam | cut -f10 | tr -d '\n' | wc -c)

    # output
    dx-jobutil-add-output subsampled_reads --class=file \
            $(dx upload --brief --destination "${reads_prefix}.trimmed_subsample.bam" subsamp.bam)
    dx-jobutil-add-output subsampled_read_pair_count --class=int $subsampled_read_pair_count
    dx-jobutil-add-output subsampled_base_count --class=int $subsampled_base_count
    dx-jobutil-add-output contigs --class=file \
            $(dx upload --brief --destination "${reads_prefix}.trinity.fasta" assembly.fasta)
}
