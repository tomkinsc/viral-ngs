#!/bin/bash

main() {
    set -e -x -o pipefail

    depletion_applet_id=$(dx-jobutil-parse-link "$depletion_applet")

    for bam in "${bams[@]}"; do
        job=$(dx run $depletion_applet_id -i "file=$bam" -i "resources=$resources" -y --brief)
        dx-jobutil-add-output --class=array:jobref cleaned_reads $job:cleaned_reads
    done
}
