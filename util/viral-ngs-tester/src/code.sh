#!/bin/bash

main() {
    set -e -x -o pipefail

    dx cat "$resources" | zcat | tar x -C /

    cd viral-ngs
    ./run_all_tests.sh
}
