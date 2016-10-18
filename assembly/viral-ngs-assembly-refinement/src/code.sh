#!/bin/bash

main() {
    set -e -x -o pipefail

    if [ -z "$name" ]; then
        name="${assembly_prefix%.scaffold}"
    fi

    pids=()
    dx cat "$resources" | pigz -dc | tar x -C / & pids+=($!)
    dx download "$assembly" -o assembly.fasta & pids+=($!)
    dx download "$reads" -o reads.bam & pids+=($!)
    mkdir gatk/
    dx cat "$gatk_tarball" | tar jx -C gatk/
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    if [ "$novocraft_license" != "" ]; then
        dx cat "$novocraft_license" > novoalign.lic
    fi

    viral-ngs novoindex /user-data/assembly.nix /user-data/assembly.fasta

    viral-ngs assembly.py refine_assembly /user-data/assembly.fasta /user-data/reads.bam /user-data/refined_assembly.fasta \
        --outVcf /user-data/sites.vcf.gz --min_coverage "$min_coverage" --major_cutoff "$major_cutoff" \
        --threads $(nproc) --GATK_PATH /user-data/gatk \
        --novo_params "$novoalign_options" --NOVOALIGN_LICENSE_PATH /user-data/novoalign.lic

    dxid="$(pigz -dc sites.vcf.gz | dx upload --destination "${name}.refinement.vcf" --brief -)"
    dx-jobutil-add-output assembly_sites_vcf --class=file "$dxid"
    dxid="$(dx upload refined_assembly.fasta --destination "${name}.refined.fasta" --brief)"
    dx-jobutil-add-output refined_assembly --class=file "$dxid"
}
