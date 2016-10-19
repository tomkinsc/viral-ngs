#!/bin/bash

main() {

    set -e -x -o pipefail

    # Unpack viral-ngs resources
    dx cat "$resources" | pigz -dc | tar x -C /

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
            dx cat "$file_id" | pigz -dc | tar xf - -C ./input/ --owner root --group root --no-same-owner
        done
    else
        # Unpack from run_tarballs, this array contain
        # Elements with spaces, so we need to quote to retain
        # the dnanexus link field intact
        for file_id in "${run_tarballs[@]}"; do
            echo "$file_id"
            dx cat "$file_id" | pigz -dc | tar xf - -C ./input/ --owner root --group root --no-same-owner
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
    # The --JVMemory arg ensures that $opts is non-empty
    mem_in_mb="`head -n1 /proc/meminfo | awk '{print int($2*0.9/1024)}'`m"
    opts=()

    if [ "$sample_sheet" != "" ]
    then
        dx cat "$sample_sheet" > "$sample_sheet_name"
        # Introduce single quotes to handle filenames with whitespace
        opts+=("--sampleSheet")
        opts+=("/user-data/${sample_sheet_name}")
    fi

    if [ "$advanced_opts" != "" ]
    then
        opts+=("$advanced_opts")
    fi

    if [ "$flowcell" != "" ]
    then
        opts+=("--flowcell")
        opts+=("$flowcell")
    fi

    if [ "$read_structure" != "" ]
    then
        opts+=("--read_structure")
        opts+=("$read_structure")
    fi

    if [ "$minimum_base_quality" != "" ]
    then
        opts+=("--minimum_base_quality")
        opts+=("$minimum_base_quality")
    fi

    if [ "$max_mismatches" != "" ]
    then
        opts+=("--max_mismatches")
        opts+=("$max_mismatches")
    fi

    if [ "$sequencing_center" != "" ]
    then
        opts+=("--sequencing_center")
        opts+=("$sequencing_center")
    fi

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

    # Make sure that the lane specified is valid
    for lane in ${lanes[@]}
    do
        if [ $lane -gt $lane_count ];
        then
            dx-jobutil-report-error "Invalid lane: $lane, there are only $lane_count lane(s) detected in the run."
        fi
    done

    for lane in ${lanes[@]}
    do
        # Prepare output folders
        bam_out_dir="out/bams"
        unmatched_out_dir="out/unmatched_bams"
        metric_out_dir="out/metrics"
        barcode_out_dir="out/barcodes"

        # Subfolders by lane if multi-lane run
        if [ "$multi_lane" = true ]; then
            bam_out_dir="$bam_out_dir/lane_$lane"
            unmatched_out_dir="$unmatched_out_dir/lane_$lane"
            metric_out_dir="$metric_out_dir/lane_$lane"
            barcode_out_dir="$barcode_out_dir/lane_$lane/"
        fi

        mkdir -p $bam_out_dir
        mkdir -p $metric_out_dir
        mkdir -p $unmatched_out_dir
        mkdir -p $barcode_out_dir

        if [ ${#opts[@]} -eq 0 ]; then
            viral-ngs illumina.py illumina_demux \
            "/user-data/$location_of_input" "$lane" "/user-data/$bam_out_dir" \
            --outMetrics "/user-data/$metric_out_dir/$metrics_fn" \
            --commonBarcodes "/user-data/$barcode_out_dir/$barcodes_fn" \
            --JVMmemory "$mem_in_mb"
        else
            # Execute viral-ngs demux, $opts is guaranteed to be
            # not empty, so we can safely quote it without introducing
            # extraneous quotes
            echo "${opts[@]}"
            viral-ngs illumina.py illumina_demux \
            "/user-data/$location_of_input" "$lane" "/user-data/$bam_out_dir" \
            --outMetrics "/user-data/$metric_out_dir/$metrics_fn" \
            --commonBarcodes "/user-data/$barcode_out_dir/$barcodes_fn" \
            --JVMmemory "$mem_in_mb" "${opts[@]}"
        fi

        # Move unmatched bam file to unmatched_out_dir, if present
        if [ -f "$bam_out_dir/Unmatched.bam" ]; then
            mv "$bam_out_dir/Unmatched.bam" "$unmatched_out_dir/"
        fi

        # Check that demuxed file is not empty (has 0 reads).
        # Remove bam file if it's empty to prevent potential issues
        # Dowstream that don't handle empty bam files elegantly
        for bam_file in `ls $bam_out_dir`
        do
            read_count=`("samtools" view -c "$bam_out_dir/$bam_file")`

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

    # add flowcell and lane properties to bams
    for lane in ${lanes[@]}; do
        bam_out_dir="/"
        if [ "$multi_lane" = true ]; then
            bam_out_dir="/lane_$lane"
        fi
        for dxfile in $(dx find data --folder "$bam_out_dir" --class file --brief); do
            if [ -n "$flowcell" ]; then
                dx set_properties "$dxfile" "flowcell=$flowcell"
            fi
            if [ "$multi_lane" = true ]; then
                dx set_properties "$dxfile" "lane=$lane"
            fi
        done
    done
}
