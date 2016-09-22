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

    # Stash the PYTHONPATH used by dx
    DX_PYTHONPATH=$PYTHONPATH
    DX_PATH=$PATH

    # Load viral-ngs virtual environment
    # Disable error propagation for now (there are warning :/ )
    unset PYTHONPATH

    set +e +o pipefail
    source easy-deploy-viral-ngs.sh load

    if [ -f /home/dnanexus/novoalign.lic ]; then
        novoalign-register-license /home/dnanexus/novoalign.lic
    fi

    gatk-register /home/dnanexus/gatk/GenomeAnalysisTK.jar

    novoindex assembly.nix assembly.fasta

    assembly.py refine_assembly assembly.fasta reads.bam refined_assembly.fasta \
        --outVcf sites.vcf.gz --min_coverage "$min_coverage" --novo_params "$novoalign_options" \
        --major_cutoff "$major_cutoff"

    # deactivate viral-ngs virtual environment
    source deactivate

    # restore paths from DX
    export PYTHONPATH=$DX_PYTHONPATH
    export PATH=$DX_PATH

    dx-jobutil-add-output assembly_sites_vcf --class=file \
        $(zcat sites.vcf.gz | dx upload --destination "${name}.refinement.vcf" --brief -)
    dx-jobutil-add-output refined_assembly --class=file \
        $(dx upload refined_assembly.fasta --destination "${name}.refined.fasta" --brief)
}
