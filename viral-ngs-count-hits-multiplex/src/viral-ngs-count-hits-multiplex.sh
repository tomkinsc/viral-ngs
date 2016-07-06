#!/bin/bash

main() {
    set -e -x -o pipefail

    if [ -z "$out_fn" ]; then
        out_fn="counts.txt"
    fi

    opts=""
    if [ -n "$novocraft_license" ]; then
        novocraft_license=$(dx-jobutil-parse-link "$novocraft_license")
        opts="-inovocraft_licence $novocraft_license $opts"
    fi

    count_hits_applet_id=$(dx-jobutil-parse-link "$count_hits_applet")

    for bam in "${in_bams[@]}"; do
        job_id=$(dx run $count_hits_applet_id \
        -iin_bam="${bam}" \
        -iresources="${resources}" \
        -iper_sample_output="${per_sample_output}" \
        -iref_fasta="${ref_fasta}" \
        -iout_fn="${out_fn}" \
        $opts --yes --brief)

        dx-jobutil-add-output count_files $job_id:count_files --class=array:jobref
    done
}
