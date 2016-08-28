#!/bin/bash

main() {

    dx-download-all-inputs --except resources

    set -e -x -o pipefail

    dx cat "$resources" | tar zx -C /

    # Stash the PYTHONPATH used by dx
    DX_PYTHONPATH=$PYTHONPATH
    DX_PATH=$PATH

    # Load viral-ngs virtual environment
    # Disable error propagation for now (there are warning :/ )
    unset PYTHONPATH

    set +e +o pipefail
    source easy-deploy-viral-ngs.sh load

    # Novoindex the reference fasta file
    index_output="${ref_fasta_path%.fasta}"
    index_output="${index_output%.fa}.nix"

    novoindex "$index_output" "$ref_fasta_path"

    # Prepare output folders
    out_dir="out/count_files"
    mkdir -p $out_dir

    if [ -z "$out_fn" ]; then
        out_fn="hit_counts.pdf"
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
    reports.py align_and_plot_coverage "${in_bam_path}"  "$out_dir/$sample_out_fn" "${ref_fasta_path}"

    # deactivate viral-ngs virtual environment
    source deactivate

    # restore paths from DX
    export PYTHONPATH=$DX_PYTHONPATH
    export PATH=$DX_PATH

    dx-upload-all-outputs
}
