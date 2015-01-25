#!/bin/bash

main() {
    set -e -x -o pipefail

    # stage the inputs
    dx cat "$resources" | zcat | tar x -C / &
    dx download "$targets" -o targets.fasta &
    dx download "$reads" -o reads.bam &
    wait

    python viral-ngs/read_utils.py bam_to_fastq reads.bam reads.fastq reads2.fastq

    # If a regex for parsing the paired read IDs was not given, attempt auto-detection
    if [ -z "$read_id_regex" ]; then
        echo "Auto-detecting paired read ID format"
        # try Illuimna basecaller format
        read_id_regex="^@(\S+)/[1|2]$"
        if ! try_read_id_regex reads.fastq "$read_id_regex"; then
            # try SRA fastq-dump format
            read_id_regex="^@(\S+).[1|2] .*"
            if ! try_read_id_regex reads.fastq "$read_id_regex"; then
                dx-jobutil-report-error "Failed to auto-detect paired read ID format in the input FASTQ files. Please explicitly specify the read_id_regex input to this applet." AppError
                exit 1
            fi
        fi
        echo "Auto-detected read_id_regex: ${read_id_regex}"
    else
        if ! try_read_id_regex reads.fastq "$read_id_regex"; then
            dx-jobutil-report-error "Failed to parse paired read ID in the input FASTQ files using the specified read_id_regex." AppError
            exit 1
        fi
    fi

    # build Lastal target database
    viral-ngs/tools/build/last-490/bin/lastdb -c targets.db targets.fasta

    # filter & dedup the reads
    python viral-ngs/taxon_filter.py filter_lastal reads.fastq targets.db filtered_reads.pre.fastq &
    python viral-ngs/taxon_filter.py filter_lastal reads2.fastq targets.db filtered_reads2.pre.fastq
    wait

    wc -l filtered_reads.pre.fastq
    wc -l filtered_reads2.pre.fastq

    # purge unmated reads
    python viral-ngs/read_utils.py purge_unmated filtered_reads.pre.fastq filtered_reads2.pre.fastq \
                                                 filtered_reads.fastq filtered_reads2.fastq \
                                                 --regex "$read_id_regex"

    # sanity checks
    read_pairs=$(expr $(wc -l < filtered_reads.fastq) / 4)
    read_pairs2=$(expr $(wc -l < filtered_reads2.fastq) / 4)
    if [ "$read_pairs" -ne "$read_pairs2" ]; then
        dx-jobutil-report-error "Reads improperly paired - this shouldn't happen! (${read_pairs} != ${read_pairs2})" AppInternalError
        exit 1
    fi
    echo "${read_pairs} read pairs survived filtering"
    if [ "$read_pairs" -lt "$min_read_pairs" ]; then
        dx-jobutil-report-error "Too few read pairs survived filtering (${read_pairs} < ${min_read_pairs})" AppError
        exit 1
    fi

    dx-jobutil-add-output unfiltered_read_pair_count $(expr $(wc -l < reads.fastq) / 4)
    dx-jobutil-add-output unfiltered_base_count $(fastq_pair_base_count reads.fastq reads2.fastq)
    dx-jobutil-add-output filtered_read_pair_count $read_pairs
    dx-jobutil-add-output filtered_base_count $(fastq_pair_base_count filtered_reads.fastq filtered_reads2.fastq)

    python viral-ngs/read_utils.py fastq_to_bam filtered_reads.fastq filtered_reads2.fastq filtered_reads.bam --sampleName "${reads_prefix%.unmapped}"
    dx-jobutil-add-output filtered_reads --class=file \
        $(dx upload --brief --destination "${reads_prefix}.filtered.bam" filtered_reads.bam)

}

try_read_id_regex() {
    head -n 1 "$1" | perl -ne "\$re='$2'; exit 0 if /\$re/; exit 1"
}

fastq_pair_base_count() {
    cat $1 $2 | paste - - - - | cut -f2 | tr -d '\n' | wc -c
}
