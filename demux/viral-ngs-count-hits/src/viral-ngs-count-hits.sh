#!/bin/bash

main() {

    dx-download-all-inputs --except resources

    set -e -x -o pipefail

    dx cat "$resources" | tar zx -C /

    # Novoindex the reference fasta file
    ref_fasta_path="in/ref_fasta/*"
    index_output="${ref_fasta_path%.fasta}"
    index_output="${index_output%.fa}.nix"

    viral-ngs novoindex "/user-data/$index_output" "/user-data/$ref_fasta_path"

    # Prepare output folders
    out_dir="out/count_files"
    mkdir -p $out_dir

    if [ -z "$out_fn" ]; then
        out_fn="hit_counts.pdf"
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

    # read_utils.py align_and_count_hits <input> <reference DB> <output>
    in_bam_path="in/in_bam/*"
    viral-ngs reports.py align_and_plot_coverage "/user-data/${in_bam_path}"  "/user-data/$out_dir/$sample_out_fn" "/user-data/${ref_fasta_path}"

    dx-upload-all-outputs
}
