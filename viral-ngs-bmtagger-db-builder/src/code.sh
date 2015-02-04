#!/bin/bash

main() {
    set -e -x -o pipefail

    dx cat "$resources" | zcat | tar x -C /
    dx cat "$fastagz" | zcat > input.fasta

    mkdir db

    bmtool -d input.fasta -o "db/${fastagz_prefix}.bitmask" -w 8
    viral-ngs/tools/build/bmtagger/srprism mkindex -i input.fasta -o "db/${fastagz_prefix}.srprism"

    cd db
    ls -lh
    dx-jobutil-add-output bmtagger_db --class=file \
        $(tar czv * | dx upload --brief --destination "${fastagz_prefix}.bmtagger_db.tar.gz" -)
}
