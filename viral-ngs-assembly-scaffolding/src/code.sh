#!/bin/bash

main() {
    set -e -x -o pipefail

    dx cat "$resources" | zcat | tar x -C / &
    dx download "$trinity_contigs" -o trinity_contigs.fa &
    dx cat "$trinity_reads" | zcat > reads.fa &
    dx cat "$trinity_reads2" | zcat > reads2.fa &
    dx download "$reference_genome" -o reference_genome.fa
    wait

    # symlink R in the path hardcoded into contigMerger.pl
    mkdir -p /broad/software/free/Linux/redhat_5_x86_64/pkgs/r_2.15.1/bin
    ln -s "$(which R)" /broad/software/free/Linux/redhat_5_x86_64/pkgs/r_2.15.1/bin/R

    # run V-FAT scripts to orient & merge contigs
    mkdir foo/
    viral-ngs/tools/scripts/vfat/orientContig.pl trinity_contigs.fa reference_genome.fa foo/bar
    viral-ngs/tools/scripts/vfat/contigMerger.pl foo/bar_orientedContigs reference_genome.fa -readfq reads.fa -readfq2 reads2.fa -fakequals 30 foo/bar
    ls -tl foo

    # check assembly quality thresholds
    python viral-ngs/assembly.py filter_short_seqs foo/bar_assembly.fa "$min_length" "$min_unambig" vfat-scaffold.fa
    if ! test -s vfat-scaffold.fa; then
        dx-jobutil-report-error "The assembly failed quality thresholds (length >= ${min_length}, non-N proportion >= ${min_unambig})" AppError
        exit 1
    fi

    # modify contig using the reference
    cat vfat-scaffold.fa reference_genome.fa | /seq/annotation/bio_tools/muscle/3.8/muscle -out muscle_align.fasta -quiet
    python viral-ngs/assembly.py modify_contig muscle_align.fasta scaffold.fa $(first_fasta_header reference_genome.fa) --name "$trinity_contigs_prefix" --call-reference-ns --trim-ends --replace-5ends --replace-3ends --replace-length "$replace_length" --replace-end-gaps
    test -s scaffold.fa

    # upload outputs
    dx-jobutil-add-output modified_scaffold --class=file \
        $(dx upload scaffold.fa --destination "${trinity_contigs_prefix}.scaffold.fasta" --brief)
    dx-jobutil-add-output vfat_scaffold --class=file \
        $(dx upload vfat-scaffold.fa --destination "${trinity_contigs_prefix}.vfat.fasta" --brief)
    dx-jobutil-add-output contigsMap --class=file \
        $(dx upload foo/bar_contigsMap.pdf --destination "${trinity_contigs_prefix}.contigsMap.pdf" --brief)
}

first_fasta_header() {
    head -n 1 "$1" | tr -d ">\n"
}
