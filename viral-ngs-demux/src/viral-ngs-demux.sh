#!/bin/bash

main() {

    set -e -x -o pipefail

    # Unpack viral-ngs resources
    export PATH="$PATH:$HOME/miniconda/bin"
    dx cat "$resources" | tar zx -C /
    samtools=viral-ngs/tools/build/conda-tools/default/bin/samtools

    # Raise error if both of upload_sentinel_record and tarballs are specified
    if [ "$upload_sentinel_record" != "" ] && [ "$run_tarballs" != "" ]; then
        dx-jobutil-report-error "Both upload sentinel and run tarballs were specified. Exactly 1 (or the other) should be specified"
    fi

    # Raise error if neither of upload_sentinel_record and tarballs are specified
    if [ "$upload_sentinel_record" == "" ] && [ "$run_tarballs" == "" ]; then
        dx-jobutil-report-error "Neither upload sentinel nor run tarballs was specified. Exactly 1 (or the other) shoud be specified"
    fi

    mkdir ./input

    # Unpack RUN directory
    if [ "$upload_sentinel_record" != "" ]; then
        # Unpack from sentinel_record

        # Get file IDs of run directory tarballs
        file_ids=$(dx get_details "$upload_sentinel_record" | jq .tar_file_ids | grep -Po '(?<=\")file-.*(?=\")')

        # This array is space separated, do not quote
        for file_id in ${file_ids[@]}; do
            dx cat "$file_id" | tar xzf - -C ./input/
        done
    else
        # Unpack from run_tarballs, this array contain
        # Elements with spaces, so we need to quote to retain
        # the dnanexus link field intact
        for file_id in "${run_tarballs[@]}"; do
            echo "$file_id"
            dx cat "$file_id" | tar xzf - -C ./input/
        done
    fi

    # Locate root of run directory
    location_of_data=$(find ./input/ -type d -name "Data")
    if [ "$location_of_data" == "" ]
    then
      dx-jobutil-report-error "The Data folder could not be found."
    fi

    location_of_input="${location_of_data%/Data}"

    # Parse the lane count from RunInfo.xml file in the root of the unpacked RUN folder
    runinfo_path=$(find $location_of_input -type f -name "RunInfo.xml" -maxdepth 1)
    if [ "$runinfo_path" == "" ]; then
        dx-jobutil-report-error "The RunInfo.xml could not be found."
    fi

    # Ensure that we have successfully parsed a lane count
    lane_count=$(xmllint --xpath "string(//Run/FlowcellLayout/@LaneCount)" "$runinfo_path")
    if [ -z lane_count ]; then
        dx-jobutil-report-error "Could not parse the number of lanes from RunInfo.xml"
    fi

    # Populate command line options
    opts="$advanced_opts"

    if [ "$sample_sheet" != "" ]
    then
        dx cat "$sample_sheet" > "$sample_sheet_name"
        opts="$opts --sampleSheet $sample_sheet_name "
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
        python viral-ngs/illumina.py illumina_demux "$location_of_input" "$lane" "$bam_out_dir" \
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
