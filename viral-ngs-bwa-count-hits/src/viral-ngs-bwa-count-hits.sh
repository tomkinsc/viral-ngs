#!/bin/bash

main() {

    dx-download-all-inputs

    set -e -x -o pipefail

    # Unpack bwa-index tarball of reference fasta, locate genome fasta
    tar xvf "${ref_fasta_tar_path}" -C ~/in/ref_fasta_tar
    genome_file=`ls in/ref_fasta_tar/*.bwt`
    genome_file="${genome_file%.bwt}"

    # Prepare output folders
    out_dir="out/count_files"
    mkdir -p $out_dir

    if [ -z "$out_fn" ]; then
        out_fn="hit_counts.txt"
    fi

    # Output file name / directory wrangling
    sample_name="${in_bam_prefix}"
    sample_out_fn="$out_fn"
    if [ "$per_sample_output" == "true" ]; then
        out_dir="$out_dir/$sample_name"
        mkdir -p "$out_dir"
    else
        sample_out_fn="$sample_name.$out_fn"
    fi

    # Perform bwa mapping
    samtools bam2fq "${in_bam_path}" | bwa mem -t `nproc` -p "$genome_file" - | samtools view -u -S - | samtools sort -m 256M -@ `nproc` - output

    # Store idxstats output as desired output file
    samtools index output.bam
    samtools idxstats output.bam > "${out_dir}/${sample_out_fn}"

    dx-upload-all-outputs
}
