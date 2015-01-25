#!/bin/bash

main() {
    set -e -x -o pipefail

    dx cat "$resources" | zcat | tar x -C / &
    dx download "$trinity_contigs" -o trinity_contigs.fa &
    dx download "$reference_genome" -o reference_genome.fa &
    dx download "$trinity_reads" -o reads.bam
    wait

    python viral-ngs/read_utils.py bam_to_fastq reads.bam reads.fa reads2.fa

    # symlink muscle and R in the paths hardcoded into contigMerger.pl
    mkdir -p /seq/annotation/bio_tools/muscle/3.8/
    ln -s /home/dnanexus/viral-ngs/tools/build/muscle3.8.31_i86linux64 /seq/annotation/bio_tools/muscle/3.8/muscle
    mkdir -p /broad/software/free/Linux/redhat_5_x86_64/pkgs/r_2.15.1/bin
    ln -s "$(which R)" /broad/software/free/Linux/redhat_5_x86_64/pkgs/r_2.15.1/bin/R

    # run V-FAT scripts to orient & merge contigs
    mkdir foo/
    vfat/orientContig.pl trinity_contigs.fa reference_genome.fa foo/bar
    vfat/contigMerger.pl foo/bar_orientedContigs reference_genome.fa \
                         -readfq reads.fa -readfq2 reads2.fa -fakequals 30 foo/bar
    ls -tl foo

    if [ -z "$name" ]; then
        name=${trinity_contigs_prefix%%.*}
        name=${name%_1}
    fi

    # HACK: assembly.py impute_from_reference calls novoindex at the end; put
    # a noop in place to trick it.
    mkdir novocraft
    cp /bin/echo novocraft/novoalign
    cp /bin/echo novocraft/novoindex
    chmod +x novocraft/novo*
    export NOVOALIGN_PATH=/home/dnanexus/novocraft

    # run assembly.py impute_from_reference to check assembly quality and clean the contigs
    exit_code=0
    python viral-ngs/assembly.py impute_from_reference foo/bar_assembly.fa reference_genome.fa scaffold.fasta \
        --newName "${name}_scaffold" --replaceLength "$replace_length" \
        --minLength "$min_length" --minUnambig "$min_unambig" \
            2> >(tee impute.stderr.log >&2) || exit_code=$?

    if [ "$exit_code" -ne "0" ]; then
        if grep PoorAssemblyError impute.stderr.log ; then
            dx-jobutil-report-error "The assembly failed quality thresholds (length >= ${min_length}, non-N proportion >= ${min_unambig})" AppError
        else
            dx-jobutil-report-error "Please check the job log" AppInternalError
        fi
        exit $exit_code
    fi

    test -s scaffold.fasta

    # upload outputs
    dx-jobutil-add-output modified_scaffold --class=file \
        $(dx upload scaffold.fasta --destination "${name}.scaffold.fasta" --brief)
    dx-jobutil-add-output vfat_scaffold --class=file \
        $(dx upload foo/bar_assembly.fa --destination "${name}.vfat.fasta" --brief)
    dx-jobutil-add-output contigsMap --class=file \
        $(dx upload foo/bar_contigsMap.pdf --destination "${name}.contigsMap.pdf" --brief)
}

first_fasta_header() {
    head -n 1 "$1" | tr -d ">\n"
}
