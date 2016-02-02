#!/bin/bash

main() {
    set -e -x -o pipefail
    export PATH="$PATH:$HOME/miniconda/bin"

    if [ -z "$name" ]; then
        name="$assembly_prefix"
    fi

    pids=()
    dx cat "$resources" | tar zx -C / & pids+=($!)
    dx download "$assembly" -o assembly.fasta & pids+=($!)
    dx download "$reads" -o reads.bam & pids+=($!)
    dx cat "$novocraft_tarball" | tar zx & pids+=($!)
    mkdir gatk/
    dx cat "$gatk_tarball" | tar jx -C gatk/
    for pid in "${pids[@]}"; do wait $pid || exit $?; done
    export NOVOALIGN_PATH=/home/dnanexus/novocraft
    export GATK_PATH=/home/dnanexus/gatk

    novocraft/novoindex assembly.nix assembly.fasta
    python viral-ngs/assembly.py refine_assembly assembly.fasta reads.bam refined_assembly.fasta \
        --outVcf sites.vcf.gz --min_coverage "$min_coverage" --novo_params "$novoalign_options" \

    dx-jobutil-add-output assembly_sites_vcf --class=file \
        $(zcat sites.vcf.gz | dx upload --destination "${name}.refinement.vcf" --brief -)
    dx-jobutil-add-output refined_assembly --class=file \
        $(dx upload refined_assembly.fasta --destination "${name}.refined.fasta" --brief)
}
