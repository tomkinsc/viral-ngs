#!/bin/bash

main() {
    set -e -x -o pipefail

    if [ -z "$name" ]; then
        name="${assembly_prefix%.scaffold}"
    fi

    pids=()
    dx cat "$resources" | tar zx -C / & pids+=($!)
    dx download "$assembly" -o assembly.fasta & pids+=($!)
    dx download "$reads" -o reads.bam & pids+=($!)
    mkdir gatk/
    dx cat "$gatk_tarball" | tar jx -C gatk/
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    viral-ngs novoindex /user-data/assembly.nix /user-data/assembly.fasta

    viral-ngs assembly.py refine_assembly /user-data/assembly.fasta /user-data/reads.bam /user-data/refined_assembly.fasta \
        --outVcf /user-data/sites.vcf.gz --min_coverage "$min_coverage" --novo_params "$novoalign_options" \
        --major_cutoff "$major_cutoff" --GATK_PATH /user-data/gatk
        # TODO: --NOVOALIGN_LICENSE_PATH ?

    dxid="$(zcat sites.vcf.gz | dx upload --destination "${name}.refinement.vcf" --brief -)"
    dx-jobutil-add-output assembly_sites_vcf --class=file "$dxid"
    dxid="$(dx upload refined_assembly.fasta --destination "${name}.refined.fasta" --brief)"
    dx-jobutil-add-output refined_assembly --class=file "$dxid"
}
