#!/bin/bash

main() {
    set -e -x -o pipefail

    filename=$(dx describe "$file" --name)
    if [[ "$filename" == *.bam ]]; then
        if [ -n "$paired_fastq" ]; then
            dx-jobutil-report-error "Received both BAM and FASTQ inputs. Provide either one unmapped BAM file or a pair of gzipped FASTQ files." AppError
            exit 1
        fi

        if [ -z "$sample_name" ]; then
            sample_name="$file_prefix"
        fi

        dx download "$file" -o input.bam
        # TODO: verify BAM is actually unmapped, contains properly paired reads, etc.
    elif [[ "$filename" == *.fastq.gz ]]; then
        if [ -z "$paired_fastq" ]; then
            dx-jobutil-report-error "Missing the second gzipped FASTQ containing mate pairs" AppError
            exit 1
        fi
        if [[ ! $(dx describe "$paired_fastq" --name) == *.fastq.gz ]]; then
            dx-jobutil-report-error "The second input file isn't a gzipped FASTQ (*.fastq.gz)" AppError
            exit 1
        fi
        
        # hack SRA FASTQ read names to make them acceptable to Picard FastqToSam
        pids=()
        dx cat "$file" | zcat | sed -r 's/(@SRR[0-9]+\.[0-9]+)\.1/\1/' | gzip -c > reads.fastq.gz & pids+=($!)
        dx cat "$paired_fastq" | zcat | sed -r 's/(@SRR[0-9]+\.[0-9]+)\.2/\1/' | gzip -c > reads2.fastq.gz & pids+=($!)
        dx cat "$resources" | zcat | tar x -C /
        for pid in "${pids[@]}"; do wait $pid || exit $?; done

        if [ -z "$sample_name" ]; then
            sample_name="${file_prefix%_1}"
            sample_name="${sample_name%.1}"
        fi

        python viral-ngs/read_utils.py fastq_to_bam reads.fastq.gz reads2.fastq.gz input.bam --sampleName "$sample_name"
    else
        dx-jobutil-report-error "The input file isn't BAM or gzipped FASTQ" AppError
        exit 1
    fi

    python viral-ngs/taxon_filter.py deplete_human input.bam \
        raw.bam bmtagger_depleted.bam rmdup.bam cleaned.bam \
        --bmtaggerDbs {params.bmtaggerDbs} --blastDbs {params.blastDbs}

    dx-jobutil-add-output all_reads --class=file \
        $(dx upload --brief --destination ${sample_name}.raw.bam raw.bam)
    dx-jobutil-add-output bmtagger_depleted_reads --class=file \
        $(dx upload --brief --destination ${sample_name}.bmtagger_depleted.bam bmtagger_depleted.bam)
    dx-jobutil-add-output rmdup_reads --class=file \
        $(dx upload --brief --destination ${sample_name}.rmdup.bam rmdup.bam)
    dx-jobutil-add-output cleaned_reads --class=file \
        $(dx upload --brief --destination ${sample_name}.cleaned.bam cleaned.bam)
}
