#!/bin/bash
# viral-ngs-demux-wrapper 0.0.1

set -e -x -o pipefail
main() {

    # Download the RunInfo.xml file
    runInfo_file_id=$(dx get_details "$upload_sentinel_record" | jq .runinfo_file_id -r)
    dx cat $runInfo_file_id > RunInfo.xml

    # Parse the lane count from RunInfo.xml file
    lane_count=$(xmllint --xpath "string(//Run/FlowcellLayout/@LaneCount)" RunInfo.xml)

    # Raise error if laneCount could not be found in the expected XML path
    if [ -z "$lane_count" ]; then
        dx-jobutil-report-error "Could not parse laneCount from RunInfo.xml. Please check RunInfo.xml is properful formatted"
    fi

    # Decide on the correct instance type to use
    if (( $lane_count > 1 ));
    then
        instance_type="mem1_ssd_x32"
        echo "Detected $lane_count lanes, interpreting as HiSeq run, executing on a $instance_type machine."
    else
        instance_type="mem1_ssd1_x4"
        echo "Detected $lane_count lane, interpreting as MiSeq run, executing on a $instance_type machine."
    fi

    # Populate command line options
    opts=""

    if [ "$sample_sheet" != "" ]
    then
        opts="$opts -isampleSheet=$sample_sheet"
    fi

    for lane in "${lanes[@]}"
    do
        opts="$opts -ilanes=$lane"
    done

    if [ "$flowcell" != "" ]
    then
        opts="$opts -iflowcell=$flowcell"
    fi

    if [ "$read_structure" != "" ]
    then
        opts="$opts -iread_structure=$read_structure"
    fi

    if [ "$sequencing_center" != "" ]
    then
        opts="$opts -isequencing_center=$sequencing_center"
    fi

    if [ "$advanced_opt" != "" ]
    then
        opts="opts -iadvanced_opt=$advanced_opt"
    fi

    echo $opts

    demux_applet_id=$(dx-jobutil-parse-link "$demux_applet")
    # Execute demux applet, shuttling all input variables as is
    # We do not quote opts as it may be empty and may be passed
    # as a confusing "" parameter if quoted
    job_id=$(dx run $demux_applet_id \
    --instance-type="$instance_type" \
    -iupload_sentinel_record="${upload_sentinel_record}" -iresources="${resources}" \
    -iper_sample_output="${per_sample_output}" $opts \
    --yes --brief)

    dx-jobutil-add-output bams $job_id:bams --class=jobref
    dx-jobutil-add-output metrics $job_id:metrics --class=jobref

}
