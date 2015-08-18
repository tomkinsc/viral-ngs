#!/bin/bash

main() {
    set -e -x -o pipefail

    accessions=$(echo ${accession_numbers[*]})
    dx cat "$resources" | tar zx -C /

    # Write combined fasta to /genome.fasta
    viral-ngs/ncbi.py fetch_fastas_and_feature_tables $user_email ./ $accessions --combinedGenomeFilePrefix genome --removeSeparateFastas

    genome_fasta=$(dx upload genome.fasta --destination "${combined_genome_prefix}.fasta" --brief)

    dx-jobutil-add-output genome_fasta "$genome_fasta" --class=file
}
