#!/bin/bash

main() {
    set -e -x -o pipefail

    accessions=$(echo ${accession_numbers[*]})
    dx cat "$resources" | tar zx -C /

    # Write combined fasta to /genome.fasta

    # there is a change to the interface for fetching fastas, feature tables, and full GenBank records
    # we need to check which commands are present and call them as appropriate.
    # since argparse returns an error code if a command is missing, and exits zero
    # if a command is present (even if arguments are missing), we can use exit codes
    # to determine the correct functions to call

    if viral-ngs/ncbi.py fetch_fastas_and_feature_tables &> /dev/null ; then
        # this is the old interface
        viral-ngs/ncbi.py fetch_fastas_and_feature_tables $user_email ./ $accessions --combinedGenomeFilePrefix genome --removeSeparateFastas
    fi

    if viral-ngs/ncbi.py fetch_fastas &> /dev/null ; then
        # this is the new interface
        viral-ngs/ncbi.py fetch_fastas $user_email ./ $accessions --combinedFilePrefix genome --removeSeparateFiles
        # if feature tables are needed, uncomment this:
        #viral-ngs/ncbi.py fetch_feature_tables $user_email ./ $accessions
    fi

    genome_fasta=$(dx upload genome.fasta --destination "${combined_genome_prefix}.fasta" --brief)

    dx-jobutil-add-output genome_fasta "$genome_fasta" --class=file
}
