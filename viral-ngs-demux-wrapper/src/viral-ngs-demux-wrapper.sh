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
        instance_type="mem1_ssd1_x32"
        echo "Detected $lane_count lanes, interpreting as HiSeq run, executing on a $instance_type machine."
    else
        instance_type="mem1_ssd1_x4"
        echo "Detected $lane_count lane, interpreting as MiSeq run, executing on a $instance_type machine."
    fi

    # Populate command line options
    opts=""

    if [ "$sample_sheet" != "" ]
    then
        opts="-isample_sheet=$sample_sheet $opts"
    fi

    for lane in "${lanes[@]}"
    do
        opts="-ilanes=$lane $opts"
    done

    if [ "$flowcell" != "" ]
    then
        opts="-iflowcell=$flowcell $opts"
    fi

    if [ "$read_structure" != "" ]
    then
        opts="-iread_structure=$read_structure $opts"
    fi

    if [ "$sequencing_center" != "" ]
    then
        opts="-isequencing_center=$sequencing_center $opts"
    fi

    if [ "$advanced_opt" != "" ]
    then
        opts="-iadvanced_opt=$advanced_opt $opts"
    fi

    echo $opts

    demux_applet_id=$(dx-jobutil-parse-link "$demux_applet")

    job_id=""

    # Execute demux applet, shuttling all input variables as is
    if [ "$opts" == "" ]
    then
        # We do not quote opts if it's empty otherwise it'll be passed
        # as a confusing "" parameter if quoted
        job_id=$(dx run $demux_applet_id \
        --instance-type="$instance_type" \
        -iupload_sentinel_record="${upload_sentinel_record}" -iresources="${resources}" \
        -iper_sample_output="${per_sample_output}" $opts \
        --yes --brief)
    else
        # If opts is not empty, we try and quote it... because of dnanexus link
        # which has whitespace
        job_id=$(dx run $demux_applet_id \
        --instance-type="$instance_type" \
        -iupload_sentinel_record="${upload_sentinel_record}" -iresources="${resources}" \
        -iper_sample_output="${per_sample_output}" "$opts" \
        --yes --brief)
    fi

    dx-jobutil-add-output bams $job_id:bams --class=jobref
    dx-jobutil-add-output metrics $job_id:metrics --class=jobref

}
