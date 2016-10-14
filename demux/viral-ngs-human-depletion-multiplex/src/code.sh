#!/bin/bash

main() {
    set -e -x -o pipefail

    depletion_applet_id=$(dx-jobutil-parse-link "$depletion_applet")

    opts=""
    if [ "$skip_depletion" = true ]; then
        opts="-i skip_depletion=true"
    fi

    for bam in "${bams[@]}"; do
        bam_name=$(dx describe --name "$bam")
        job=$(dx run $depletion_applet_id -i "file=$bam" \
        -i "resources=$resources" -i "per_sample_output=$per_sample_output" \
        $opts --name "deplete $bam_name" -y --brief)
        dx-jobutil-add-output --class=array:jobref cleaned_reads $job:cleaned_reads
    done
}
