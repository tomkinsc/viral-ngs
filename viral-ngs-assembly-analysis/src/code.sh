#!/bin/bash

main() {
    set -e -x -o pipefail

    if [ -z "$name" ]; then
        name="${assembly_prefix%.refined.refined}"
    fi

    pids=()
    dx cat "$resources" | tar zx -C / & pids+=($!)
    dx download "$assembly" -o assembly.fasta & pids+=($!)
    dx download "$reads" -o reads.bam & pids+=($!)
    mkdir gatk/
    dx cat "$gatk_tarball" | tar jx -C gatk/
    for pid in "${pids[@]}"; do wait $pid || exit $?; done

    if [ "$novocraft_license" != "" ]; then
        dx cat "$novocraft_license" > /home/dnanexus/novoalign.lic
    fi

    # Stash the PYTHONPATH used by dx
    DX_PYTHONPATH=$PYTHONPATH
    DX_PATH=$PATH

    # Load viral-ngs virtual environment
    # Disable error propagation for now (there are warning :/ )
    unset PYTHONPATH

    set +e +o pipefail
    export SKIP_VERSION_CHECK=1
    source easy-deploy-viral-ngs.sh load

    if [ -f /home/dnanexus/novoalign.lic ]; then
        novoalign-register-license /home/dnanexus/novoalign.lic
    fi

    gatk-register /home/dnanexus/gatk/GenomeAnalysisTK.jar

    read_utils.py index_fasta_picard assembly.fasta
    read_utils.py index_fasta_samtools assembly.fasta

    # Prep fasta: index using novoalign
    novoindex assembly.nix assembly.fasta

    # align reads, dedup, realign, filter
    read_utils.py align_and_fix reads.bam assembly.fasta --outBamAll all.bam --outBamFiltered mapped.bam --aligner_options "$novoalign_options"
    samtools index mapped.bam

    reports.py plot_coverage mapped.bam coverage_plot.pdf --plotFormat pdf --plotWidth 1100 --plotHeight 850 --plotDPI 100

    # collect some statistics
    assembly_length=$(tail -n +1 assembly.fasta | tr -d '\n' | wc -c)
    alignment_read_count=$(samtools view -c mapped.bam)
    reads_paired_count=$(samtools flagstat all.bam | grep properly | awk '{print $1}')
    alignment_base_count=$(samtools view mapped.bam | cut -f10 | tr -d '\n' | wc -c)
    mean_coverage_depth=$(expr $alignment_base_count / $assembly_length)
    samtools flagstat  all.bam > stats.txt

    # deactivate viral-ngs virtual environment
    source deactivate

    # restore paths from DX
    export PYTHONPATH=$DX_PYTHONPATH
    export PATH=$DX_PATH

    # Continue gathering statistics
    genomecov=$(bedtools genomecov -ibam mapped.bam | dx upload -o "${name}.genomecov.txt" --brief -)

    # upload outputs
    dx-jobutil-add-output assembly_length $assembly_length
    dx-jobutil-add-output reads_paired_count $reads_paired_count
    dx-jobutil-add-output alignment_read_count $alignment_read_count
    dx-jobutil-add-output alignment_base_count $alignment_base_count
    dx-jobutil-add-output mean_coverage_depth $mean_coverage_depth
    dx-jobutil-add-output all_reads --class=file \
        $(dx upload all.bam --destination "${name}.all.bam" --brief)
    dx-jobutil-add-output bam_stat --class=file \
        $(dx upload stats.txt --destination "${name}.flagstat.txt" --brief)
    dx-jobutil-add-output assembly_read_alignments --class=file \
        $(dx upload mapped.bam --destination "${name}.mapped.bam" --brief)
    dx-jobutil-add-output assembly_read_index --class=file \
        $(dx upload mapped.bam.bai --destination "${name}.mapped.bam.bai" --brief)
    dx-jobutil-add-output alignment_genomecov "$genomecov"
    dx-jobutil-add-output final_assembly --class=file \
        $(dx upload assembly.fasta --destination "${name}.fasta" --brief)
    dx-jobutil-add-output coverage_plot --class=file \
        $(dx upload coverage_plot.pdf --destination "${name}.coverage_plot.pdf" --brief)
}
