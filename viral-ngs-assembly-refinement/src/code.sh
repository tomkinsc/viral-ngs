#!/bin/bash

main() {
    set -e -x -o pipefail

    if [ -z "$name" ]; then
        name="$assembly_prefix"
    fi

    dx cat "$resources" | tar zx -C / &
    dx download "$assembly" -o assembly.fa &
    dx cat "$reads" | zcat > reads.fa &
    dx cat "$reads2" | zcat > reads2.fa &
    dx cat "$novocraft_tarball" | tar zx &
    dx cat "$gatk_tarball" | tar jx
    wait

    # Novoalign reads back to the assembly
    python viral-ngs/assembly.py deambig_fasta assembly.fa assembly.deambig.fa
    python viral-ngs/read_utils.py index_fasta_picard assembly.deambig.fa
    python viral-ngs/read_utils.py index_fasta_samtools assembly.deambig.fa
    novocraft/novoindex assembly.deambig.fa.nix assembly.deambig.fa

    novocraft/novoalign $novoalign_options -f reads.fa reads2.fa \
                        -F STDFQ -o SAM -d assembly.deambig.fa.nix \
        | viral-ngs/tools/build/samtools-0.1.19/samtools view -buS -q 1 - \
        | java -Xmx2g -jar viral-ngs/tools/build/picard-tools-1.126/picard.jar SortSam \
                      SO=coordinate VALIDATION_STRINGENCY=SILENT \
                      I=/dev/stdin O=reads.bam

    # set read group
    java -Xmx2g -jar viral-ngs/tools/build/picard-tools-1.126/picard.jar AddOrReplaceReadGroups \
                     VALIDATION_STRINGENCY=SILENT RGLB=UNKNOWN RGPL=ILLUMINA RGPU=UNKNOWN "RGSM=${name}" \
                     I=reads.bam O=reads.rg.bam

    # deduplicate
    python viral-ngs/read_utils.py mkdup_picard reads.rg.bam reads.rg.dedup.bam \
                                                --remove --picardOptions CREATE_INDEX=true

    # realign indels
    java -Xmx2g -jar GenomeAnalysisTK.jar -T RealignerTargetCreator \
                -R assembly.deambig.fa -o target.intervals -I reads.rg.dedup.bam
    java -Xmx2g -jar GenomeAnalysisTK.jar -T IndelRealigner \
                -R assembly.deambig.fa -targetIntervals target.intervals \
                -I reads.rg.dedup.bam -o reads.realigned.dedup.bam

    # run UnifiedGenotyper
    java -Xmx2g -jar GenomeAnalysisTK.jar -T UnifiedGenotyper \
                -R assembly.deambig.fa -I reads.realigned.dedup.bam -o sites.vcf \
                --min_base_quality_score 15 -ploidy 4 -glm BOTH --baq OFF \
                --useOriginalQualities -out_mode EMIT_ALL_SITES -dt NONE --num_threads $(nproc) \
                -stand_call_conf 0 -stand_emit_conf 0 -A AlleleBalance
    bgzip -c sites.vcf > sites.vcf.gz
    tabix sites.vcf.gz

    # generate the final assembly
    python viral-ngs/assembly.py vcf_to_fasta sites.vcf.gz refined_assembly.fa --min_coverage "$min_coverage" --trim_ends --name "${name}.refined"

    # upload outputs
    dx-jobutil-add-output deambig_assembly --class=file \
        $(dx upload assembly.deambig.fa --destination "${name}.deambig.fasta" --brief)
    dx-jobutil-add-output assembly_read_alignments --class=file \
        $(dx upload reads.realigned.dedup.bam --destination "${name}.refinement.bam" --brief)
    dx-jobutil-add-output assembly_sites_vcf --class=file \
        $(dx upload sites.vcf --destination "${name}.refinement.vcf" --brief)
    dx-jobutil-add-output refined_assembly --class=file \
        $(dx upload refined_assembly.fa --destination "${name}.refined.fasta" --brief)
}
