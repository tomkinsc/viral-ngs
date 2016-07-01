#!/bin/bash

samtools=/home/dnanexus/viral-ngs/tools/conda-cache/.pkgs/samtools-1.2-2/bin/samtools

main() {
    set -e -x -o pipefail
    export PATH="$PATH:$HOME/miniconda/bin"

    # stage the inputs
    pids=()
    dx cat "$resources" | zcat | tar x -C / & pids+=($!)
    dx download "$reads" -o reads.bam & pids+=($!)
    dx download "$contaminants" -o contaminants.fasta
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    ulimit -s unlimited
    exit_code=0

    # run trinity
    python viral-ngs/assembly.py assemble_trinity reads.bam \
    contaminants.fasta assembly.fasta --n_reads=$subsample \
    --outReads subsamp.bam 2> >(tee trinity.stderr.log >&2) || exit_code=$?

    # Check for DenovoAssemblyError raised by assemble_trinity
    if [ "$exit_code" -ne "0" ]; then
        if grep DenovoAssemblyError trinity.stderr.log ; then
            dx-jobutil-report-error "DenovoAssemblyError raised by assemble_trinity step. Please check job log for detailed information." AppError
        else
            dx-jobutil-report-error "Please check the job log" AppInternalError
        fi
        exit $exit_code
    fi

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
