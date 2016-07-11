#!/bin/bash

main() {
    set -e -x -o pipefail
    export PATH="$PATH:$HOME/miniconda/bin"

    pids=()
    dx cat "$resources" | zcat | tar x -C / & pids+=($!)
    dx download "$trinity_contigs" -o trinity_contigs.fasta & pids+=($!)
    dx download "$reference_genome" -o reference_genome.fasta & pids+=($!)
    dx download "$trinity_reads" -o reads.bam
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    if [ "$novocraft_license" != "" ]; then
        dx cat "$novocraft_license" > /home/dnanexus/novoalign.lic
        export NOVOALIGN_LICENSE_PATH=/home/dnanexus/novoalign.lic
    fi

    # run assembly.py order_and_orient to scaffold the contigs
    python viral-ngs/assembly.py order_and_orient \
        trinity_contigs.fasta reference_genome.fasta intermediate_scaffold.fasta

    if [ -z "$name" ]; then
        name=${trinity_contigs_prefix%_1}
    fi

    # run assembly.py impute_from_reference to check assembly quality and clean the contigs
    exit_code=0
    python viral-ngs/assembly.py impute_from_reference \
        intermediate_scaffold.fasta reference_genome.fasta scaffold.fasta \
        --newName "${name}" --replaceLength "$replace_length" \
        --minLengthFraction "$min_length_fraction" --minUnambig "$min_unambig" \
        --aligner "$aligner" 2> >(tee impute.stderr.log >&2) || exit_code=$?

    if [ "$exit_code" -ne "0" ]; then
        if grep PoorAssemblyError impute.stderr.log ; then
            dx-jobutil-report-error "The assembly failed quality thresholds (length fraction >= ${min_length_fraction}, non-N proportion >= ${min_unambig})" AppError
        else
            dx-jobutil-report-error "Please check the job log" AppInternalError
        fi
        exit $exit_code
    fi

    test -s scaffold.fasta

    # upload outputs
    dx-jobutil-add-output modified_scaffold --class=file \
        $(dx upload scaffold.fasta --destination "${name}.scaffold.fasta" --brief)
    dx-jobutil-add-output intermediate_scaffold --class=file \
        $(dx upload intermediate_scaffold.fasta --destination "${name}.mummer.fasta" --brief)
}

first_fasta_header() {
    head -n 1 "$1" | tr -d ">\n"
}
