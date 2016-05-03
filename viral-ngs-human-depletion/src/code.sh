#!/bin/bash

samtools=viral-ngs/tools/build/conda-tools/default/bin/samtools

main() {
    set -e -x -o pipefail
    export PATH="$PATH:$HOME/miniconda/bin"

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

        python viral-ngs/read_utils.py fastq_to_bam reads.fastq.gz reads2.fastq.gz input.bam --sampleName "$sample_name"

        if [ "$skip_depletion" == "true" ]; then
            dx-jobutil-add-output cleaned_reads --class=file \
                $(dx upload --brief --destination ${sample_name}.unmapped.bam input.bam)
            # will quit below after counting reads/bases
        fi
    else
        dx-jobutil-report-error "The input file doesn't appear to be BAM or FASTQ" AppError
        exit 1
    fi

    # count reads and bases in the input
    predepletion_read_count=$($samtools view -c input.bam)
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
    pids=()
    mkdir bmtagger_db
    local_bmtagger_dbs=""
    for tarball in "${bmtagger_dbs[@]}"; do
        dbname=$(dx describe "$tarball" --name)
        dbname=${dbname%.bmtagger_db.tar.gz}
        mkdir "bmtagger_db/${dbname}"
        local_bmtagger_dbs="${local_bmtagger_dbs} bmtagger_db/${dbname}/${dbname}"
        dx cat "$tarball" | zcat | tar x -C "bmtagger_db/${dbname}" & pids+=($!)
    done

    mkdir blast_db
    local_blast_dbs=""
    for tarball in "${blast_dbs[@]}"; do
        dbname=$(dx describe "$tarball" --name)
        dbname=${dbname%.blastndb.tar.gz}
        mkdir "blast_db/${dbname}"
        local_blast_dbs="${local_blast_dbs} blast_db/${dbname}/${dbname}"
        dx cat "$tarball" | zcat | tar x -C "blast_db/${dbname}" & pids+=($!)
    done

    for pid in "${pids[@]}"; do wait $pid || exit $?; done
    find bmtagger_db -type f
    find blast_db -type f

    # find 90% memory, for java
    mem_in_mb=`head -n1 /proc/meminfo | awk '{print int($2*0.9/1024)}'`

    # run deplete_human
    python viral-ngs/taxon_filter.py deplete_human \
        --JVMmemory ${mem_in_mb}m --threads `nproc` \
        input.bam raw.bam bmtagger_depleted.bam rmdup.bam cleaned.bam \
        --bmtaggerDbs $local_bmtagger_dbs --blastDbs $local_blast_dbs

    # upload outputs
    dx-jobutil-add-output depleted_read_count --class=int \
        $($samtools view -c cleaned.bam)
    dx-jobutil-add-output depleted_base_count --class=int \
        $(bam_base_count cleaned.bam)
    dx-jobutil-add-output intermediates --class=array:file \
        $(dx upload --brief --destination ${sample_name}.raw.bam raw.bam)
    dx-jobutil-add-output intermediates --class=array:file \
        $(dx upload --brief --destination ${sample_name}.bmtagger_depleted.bam bmtagger_depleted.bam)
    dx-jobutil-add-output intermediates --class=array:file \
        $(dx upload --brief --destination ${sample_name}.rmdup.bam rmdup.bam)
    dx-jobutil-add-output cleaned_reads --class=file \
        $(dx upload --brief --destination ${sample_name}.cleaned.bam cleaned.bam)
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
    $samtools view $1 | cut -f10 | tr -d '\n' | wc -c
}
