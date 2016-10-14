#!/bin/bash

main() {
    set -e -x -o pipefail

    # Receive the input reads as either a BAM file or a pair of FASTQs
    filename=$(dx describe "$file" --name)
    if [[ "$filename" == *.bam ]]; then
        if [ -n "$paired_fastq" ]; then
            dx-jobutil-report-error "Received both BAM and FASTQ inputs. Provide either one unmapped BAM file or a pair of FASTQ files." AppError
            exit 1
        fi

        if [ -z "$sample_name" ]; then
            sample_name="$file_prefix"
            sample_name="${sample_name%.raw}"
        fi

        pids=()
        dx cat "$resources" | zcat | tar x -C / & pids+=($!)
        dx download "$file" -o input.bam
        for pid in "${pids[@]}"; do wait $pid || exit $?; done
        # TODO: verify BAM is actually unmapped, contains properly paired reads, etc.

        if [ "$skip_depletion" == "true" ]; then
            dx-jobutil-add-output cleaned_reads --class=file "$file"
            # will quit below after counting reads/bases
        fi
    elif [[ "$filename" == *.fastq.gz || "$filename" == *.fastq ]]; then
        if [ -z "$paired_fastq" ]; then
            dx-jobutil-report-error "Missing the second FASTQ file containing mate pairs" AppError
            exit 1
        fi
        paired_fastq_name=$(dx describe "$paired_fastq" --name)
        if [[ "$paired_fastq_name" != *.fastq.gz && "$paired_fastq_name" != *.fastq ]]; then
            dx-jobutil-report-error "The second input file doesn't appear to be a FASTQ file (*.fastq or *.fastq.gz)" AppError
            exit 1
        fi

        pids=()
        dx cat "$resources" | zcat | tar x -C / & pids+=($!)
        # hack SRA FASTQ read names to make them acceptable to Picard FastqToSam
        maybe_dxzcat "$file" | sed -r 's/(@SRR[0-9]+\.[0-9]+)\.1/\1/' | gzip -c > reads.fastq.gz & pids+=($!)
        maybe_dxzcat "$paired_fastq" | sed -r 's/(@SRR[0-9]+\.[0-9]+)\.2/\1/' | gzip -c > reads2.fastq.gz
        for pid in "${pids[@]}"; do wait $pid || exit $?; done

        if [ -z "$sample_name" ]; then
            sample_name="${file_prefix%_1}"
            sample_name="${sample_name%.1}"
        fi

        viral-ngs read_utils.py fastq_to_bam /user-data/reads.fastq.gz /user-data/reads2.fastq.gz /user-data/input.bam --sampleName "$sample_name"

        if [ "$skip_depletion" == "true" ]; then
            dxid=$(dx upload --brief --destination "${sample_name}.unmapped.bam" input.bam)
            dx-jobutil-add-output cleaned_reads --class=file "$dxid"
            # will quit below after counting reads/bases
        fi
    else
        dx-jobutil-report-error "The input file doesn't appear to be BAM or FASTQ" AppError
        exit 1
    fi

    # count reads and bases in the input
    predepletion_read_count=$(samtools view -c input.bam)
    predepletion_base_count=$(bam_base_count input.bam)

    dx-jobutil-add-output predepletion_read_count --class=int "$predepletion_read_count"
    dx-jobutil-add-output predepletion_base_count --class=int "$predepletion_base_count"

    if [ "$skip_depletion" == "true" ]; then
        dx-jobutil-add-output depleted_read_count --class=int "$predepletion_read_count"
        dx-jobutil-add-output depleted_base_count --class=int "$predepletion_base_count"
        # cleaned_reads output was set above
        exit 0
    fi


    # stage the databases for BMTagger and BLAST
    # assumptions: each database is stored in a tarball. If the database name
    # is X then the tarball is named X.bmtagger_db.tar.gz or X.blastndb.tar.gz.
    # The tarball contains the database files in the root (NOT in subdirectory
    # X/). The individual database files have X as their base name, e.g.
    # X.srprism.amp, X.nin
    pids=()
    mkdir bmtagger_db
    local_bmtagger_dbs=""
    for tarball in "${bmtagger_dbs[@]}"; do
        dbname=$(dx describe "$tarball" --name)
        dbname=${dbname%.bmtagger_db.tar.gz}
        mkdir "bmtagger_db/${dbname}"
        local_bmtagger_dbs="${local_bmtagger_dbs} /user-data/bmtagger_db/${dbname}/${dbname}"
        dx cat "$tarball" | zcat | tar x -C "bmtagger_db/${dbname}" & pids+=($!)
    done

    mkdir blast_db
    local_blast_dbs=""
    for tarball in "${blast_dbs[@]}"; do
        dbname=$(dx describe "$tarball" --name)
        dbname=${dbname%.blastndb.tar.gz}
        mkdir "blast_db/${dbname}"
        local_blast_dbs="${local_blast_dbs} /user-data/blast_db/${dbname}/${dbname}"
        dx cat "$tarball" | zcat | tar x -C "blast_db/${dbname}" & pids+=($!)
    done

    for pid in "${pids[@]}"; do wait $pid || exit $?; done
    find bmtagger_db -type f
    find blast_db -type f

    # find 90% memory, for java
    mem_in_mb=`head -n1 /proc/meminfo | awk '{print int($2*0.9/1024)}'`

    # run deplete_human
    viral-ngs taxon_filter.py deplete_human \
        --JVMmemory ${mem_in_mb}m --threads `nproc` \
        /user-data/input.bam /user-data/raw.bam /user-data/bmtagger_depleted.bam \
        /user-data/rmdup.bam /user-data/cleaned.bam \
        --bmtaggerDbs $local_bmtagger_dbs --blastDbs $local_blast_dbs

    depleted_read_count=$(samtools view -c cleaned.bam)
    depleted_base_count=$(bam_base_count cleaned.bam)

    # upload outputs
    dx-jobutil-add-output depleted_read_count --class=int $depleted_read_count
    dx-jobutil-add-output depleted_base_count --class=int $depleted_base_count

    cleaned_reads_out_folder="out/cleaned_reads"
    intermediates_out_folder="out/intermediates"

    if [ "$per_sample_output" == "true" ]; then
        # folder structure for multi-lane outputs uses lane metadata recorded
        # in BAM property at the end of demux
        lane=$(dx describe --json "$file" | jq -r .properties.lane)
        if [ "$lane" == "null" ]; then
            cleaned_reads_out_folder="out/cleaned_reads/${sample_name}"
            intermediates_out_folder="out/intermediates/${sample_name}"
        else
            cleaned_reads_out_folder="out/cleaned_reads/lane_$lane/${sample_name}"
            intermediates_out_folder="out/intermediates/lane_$lane/${sample_name}"
        fi
    fi

    mkdir -p $cleaned_reads_out_folder
    mkdir -p $intermediates_out_folder

    mv raw.bam "${intermediates_out_folder}/${sample_name}.raw.bam"
    mv bmtagger_depleted.bam "${intermediates_out_folder}/${sample_name}.bmtagger_depleted.bam"
    mv rmdup.bam "${intermediates_out_folder}/${sample_name}.rmdup.bam"

    mv cleaned.bam "${cleaned_reads_out_folder}/${sample_name}.cleaned.bam"

    dx-upload-all-outputs
}

maybe_dxzcat() {
    name=$(dx describe "$1" --name)
    if [[ "$name" == *.gz ]]; then
        dx cat "$1" | zcat
    else
        dx cat "$1"
    fi
}

bam_base_count() {
    samtools view $1 | cut -f10 | tr -d '\n' | wc -c
}
