#!/bin/bash

main() {

    set -e -x -o pipefail

    # Unpack viral-ngs resources
    export PATH="$PATH:$HOME/miniconda/bin"
    dx cat "$resources" | tar zx -C /
    samtools=viral-ngs/tools/build/conda-tools/default/bin/samtools

     # Download the RunInfo.xml file
    runInfo_file_id=$(dx get_details "$upload_sentinel_record" | jq .runinfo_file_id -r)
    dx cat $runInfo_file_id > RunInfo.xml

    # Parse the lane count from RunInfo.xml file
    lane_count=$(xmllint --xpath "string(//Run/FlowcellLayout/@LaneCount)" RunInfo.xml)

    # Raise error if laneCount could not be found in the expected XML path
    if [ -z "$lane_count" ]; then
        dx-jobutil-report-error "Could not parse laneCount from RunInfo.xml. Please check RunInfo.xml is properful formatted"
    fi

    # Get file IDs of run directory tarballs
    mkdir ./input
    file_ids=$(dx get_details "$upload_sentinel_record" | jq .tar_file_ids | grep -Po '(?<=\")file-.*(?=\")')

    # This has to be done in order, so no parallelization
    for file_id in ${file_ids[@]}; do
        dx cat $file_id | tar xzf - -C ./input/ --owner root --group root --no-same-owner
    done

    # Locate root of run directory
    location_of_data=$(find . -type d -name "Data")
    if [ "$location_of_data" == "" ]
    then
      dx-jobutil-report-error "The Data folder could not be found."
    fi

    # Populate command line options
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

    if [ "$sequencing_center" != "" ]
    then
        opts="$opts --sequencing_center $sequencing_center "
    fi

    mem_in_mb="`head -n1 /proc/meminfo | awk '{print int($2*0.9/1024)}'`m"

    # Find the lanes to perform demux on, if no lanes
    # specified, demux over all lanes
    if [ ${#lanes[@]} -eq 0 ];
    then
        lanes=$(seq 1 $lane_count)
    fi

    multi_lane=false

    if [ "${#lanes}" -gt 1 ];
    then
        multi_lane=true
    fi

    # Perform demux iteratively over lanes
    for lane in ${lanes[@]}
    do
        # Make sure that the lane specified is valid
        if [ $lane -gt $lane_count ];
        then
            dx-jobutil-report-error "Invalid lane: $lane, there are only $lane_count lane(s) detected in the run."
        fi

        # Prepare output folders
        bam_out_dir="out/bams"
        metric_out_dir="out/metrics"

        # Subfolders by lane if multi-lane run
        if [ "$multi_lane" = true ]; then
            bam_out_dir="out/bams/lane_$lane"
            metric_out_dir="out/metrics/lane_$lane"
        fi

        mkdir -p $bam_out_dir
        mkdir -p $metric_out_dir

        # Execute viral-ngs demux, $opts may be empty so we do not quote it
        # to prevent expansion to an empty "" argument
        python viral-ngs/illumina.py illumina_demux input/ "$lane" "$bam_out_dir" \
        --outMetrics "$metric_out_dir/$metrics_fn" --JVMmemory "$mem_in_mb" \
        $opts

        # Check that demuxed file is not empty (has 0 reads).
        # Remove bam file if it's empty to prevent potential issues
        # Dowstream that don't handle empty bam files elegantly
        for bam_file in `ls $bam_out_dir`
        do
            read_count=`("$samtools" view -c "$bam_out_dir/$bam_file")`

            if [ $read_count -eq 0 ]; then
                echo "===WARNING=== No reads found in demuxed bam file: $bam_file. This file will be removed from output"
                # Remove empty file
                rm "$bam_out_dir/$bam_file"
            fi
        done

        # Per sample output, make output sub-folder for each sample
        if [ "$per_sample_output" = 'true' ]; then
            for file in `ls $bam_out_dir`
            do
                sample_name="${file%.bam}"
                mkdir -p "$bam_out_dir/$sample_name"
                mv "$bam_out_dir/$file" "$bam_out_dir/$sample_name/$file"
            done
        fi
    done

    dx-upload-all-outputs

}
