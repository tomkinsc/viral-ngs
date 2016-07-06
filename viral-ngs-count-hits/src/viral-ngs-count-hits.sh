#!/bin/bash

main() {

    dx-download-all-inputs --except resources

    set -e -x -o pipefail

    # resources includes Novoalign
    dx cat "$resources" | tar zx -C /
    export PATH="$PATH:$HOME/miniconda/bin"

    # Novoindex the reference fasta file
    novoindex="/home/dnanexus/viral-ngs/tools/conda-tools/default/bin/novoindex"
    index_output="${ref_fasta_path%.fasta}"
    index_output="${index_output%.fa}.nix"

    $novoindex "$index_output" "$ref_fasta_path"

    # Prepare output folders
    out_dir="out/count_files"
    mkdir -p $out_dir

    if [ -z "$out_fn" ]; then
        out_fn="hit_counts.txt"
    fi

    # Output file name / directory wrangling
    sample_name="${in_bam_prefix}"
    sample_out_fn=$out_fn
    if [ "$per_sample_output" == "true" ]; then
        out_dir="$out_dir/$sample_name"
        mkdir -p "$out_dir"
    else
        sample_out_fn="$sample_name.$out_fn"
    fi

    # read_utils.py align_and_count_hits <input> <reference DB> <output>
    viral-ngs/read_utils.py align_and_count_hits "${in_bam_path}" "${ref_fasta_path}" "$out_dir/$sample_out_fn"

    dx-upload-all-outputs
}
