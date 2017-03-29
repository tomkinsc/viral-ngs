#!/bin/bash

main() {
    set -e -x -o pipefail

    # stage the inputs
    pids=()
    dx cat "$resources" | pigz -dc | tar x -C / & pids+=($!)
    dx download "$reads" -o reads.bam & pids+=($!)
    dx download "$contaminants" -o contaminants.fasta
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    ulimit -s unlimited
    exit_code=0

    # run trinity
    viral-ngs assembly.py assemble_trinity /user-data/reads.bam \
        /user-data/contaminants.fasta /user-data/assembly.fasta --n_reads=$subsample \
        --outReads /user-data/subsamp.bam 2> >(tee trinity.stderr.log >&2) || exit_code=$?

    # collect figures of merit
    subsampled_read_count=$(samtools view -c subsamp.bam)
    subsampled_read_pair_count=$(( subsampled_read_count / 2))
    subsampled_base_count=$(samtools view subsamp.bam | cut -f10 | tr -d '\n' | wc -c)

    # Check for DenovoAssemblyError raised by assemble_trinity
    if [ "$exit_code" -ne "0" ]; then
        if grep DenovoAssemblyError trinity.stderr.log ; then
            dx-jobutil-report-error "DenovoAssemblyError raised by assemble_trinity step. Please check job log for detailed information." AppError
        else
            dx-jobutil-report-error "Please check the job log" AppInternalError
        fi
        exit $exit_code
    fi

    # output
    dxid=$(dx upload --brief --destination "${reads_prefix}.trimmed_subsample.bam" subsamp.bam)
    dx-jobutil-add-output subsampled_reads --class=file "$dxid"
    dx-jobutil-add-output subsampled_read_pair_count --class=int $subsampled_read_pair_count
    dx-jobutil-add-output subsampled_base_count --class=int $subsampled_base_count
    dxid=$(dx upload --brief --destination "${reads_prefix}.trinity.fasta" assembly.fasta)
    dx-jobutil-add-output contigs --class=file "$dxid"
}

bam_base_count() {
    samtools view $1 | cut -f10 | tr -d '\n' | wc -c
}
