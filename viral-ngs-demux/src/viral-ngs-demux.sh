#!/bin/bash

main() {

    set -e -x -o pipefail

    export PATH="$PATH:$HOME/miniconda/bin"
    dx cat "$resources" | tar zx -C /

    mkdir ./input
    file_ids=$(dx get_details "$upload_sentinel_record" | jq .tar_file_ids | grep -Po '(?<=\")file-.*(?=\")')

    # This has to be done in order, so no parallelization
    for file_id in ${file_ids[@]}; do
        dx cat $file_id | tar xzf - -C ./input/
    done

    location_of_data=$(find . -type d -name "Data")
    if [ "$location_of_data" == "" ]

    then
      dx-jobutil-report-error "The Data folder could not be found."
    fi

    opts="$advanced_opts"

    if [ "$sample_sheet" != "" ]
    then
        dx cat "$sample_sheet" > SampleSheet.txt
        opts="$opts --sampleSheet SampleSheet.txt "
    fi

    if [ "$flowcell" != "" ]
    then
        opts="$opts --flowcell $flowcell "
    fi

    if [ "$read_structure" != "" ]
    then
        opts="$opts --read_structure $read_structure "
    fi

    mem_in_mb="`head -n1 /proc/meminfo | awk '{print int($2*0.9/1024)}'`m"

    mkdir -p out/bams
    mkdir -p out/metrics

    python viral-ngs/illumina.py illumina_demux  input/ $lane out/bams/ \
    --outMetrics out/metrics/$metrics_fn --JVMmemory $mem_in_mb \
    $opts

    sleep 1200

    dx-upload-all-outputs

}
