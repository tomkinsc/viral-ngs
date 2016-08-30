#!/bin/bash

samtools=/home/dnanexus/viral-ngs/tools/conda-tools/default/bin/samtools

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

    # Stash the PYTHONPATH used by dx
    DX_PYTHONPATH=$PYTHONPATH
    DX_PATH=$PATH

    # Load viral-ngs virtual environment
    # Disable error propagation for now (there are warning :/ )
    unset PYTHONPATH

    set +e +o pipefail
    source easy-deploy-viral-ngs.sh load

    # run trinity
    assembly.py assemble_trinity reads.bam \
    contaminants.fasta assembly.fasta --n_reads=$subsample \
    --outReads subsamp.bam 2> >(tee trinity.stderr.log >&2) || exit_code=$?

    # collect figures of merit
    subsampled_read_count=$(samtools view -c subsamp.bam)
    subsampled_read_pair_count=$(expr $subsampled_read_count / 2)
    subsampled_base_count=$(samtools view subsamp.bam | cut -f10 | tr -d '\n' | wc -c)

    # deactivate viral-ngs virtual environment
    source deactivate

    # restore paths from DX
    export PYTHONPATH=$DX_PYTHONPATH
    export PATH=$DX_PATH

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
