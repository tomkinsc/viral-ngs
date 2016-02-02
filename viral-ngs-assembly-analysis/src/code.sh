#!/bin/bash

main() {
    set -e -x -o pipefail
    export PATH="$PATH:$HOME/miniconda/bin"

    if [ -z "$name" ]; then
        name="${assembly_prefix%.refined.refined}"
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

    python viral-ngs/read_utils.py index_fasta_picard assembly.fasta
    python viral-ngs/read_utils.py index_fasta_samtools assembly.fasta
    novocraft/novoindex assembly.nix assembly.fasta
    samtools=miniconda/pkgs/samtools-1.2-2/bin/samtools

    # align reads, dedup, realign, filter
    python viral-ngs/read_utils.py align_and_fix reads.bam assembly.fasta --outBamAll all.bam --outBamFiltered mapped.bam --novoalign_options "$novoalign_options"

    # collect some statistics
    assembly_length=$(tail -n +1 assembly.fasta | tr -d '\n' | wc -c)
    alignment_read_count=$($samtools view -c mapped.bam)
    reads_paired_count=$($samtools flagstat all.bam | grep properly | awk '{print $1}')
    alignment_base_count=$($samtools view mapped.bam | cut -f10 | tr -d '\n' | wc -c)
    mean_coverage_depth=$(expr $alignment_base_count / $assembly_length)
    genomecov=$(bedtools genomecov -ibam mapped.bam | dx upload -o "${name}.genomecov.txt" --brief -)
    $samtools flagstat  all.bam > stats.txt

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
    dx-jobutil-add-output alignment_genomecov "$genomecov"
    dx-jobutil-add-output final_assembly --class=file \
        $(dx upload assembly.fasta --destination "${name}.fasta" --brief)
}
