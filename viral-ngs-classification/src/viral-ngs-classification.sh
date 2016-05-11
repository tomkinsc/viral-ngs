#!/bin/bash

# (https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html)
#   - `-e`: Exit immediately if any pipeline returns nonzero status.
#   - `-o pipefail`: Return value of pipeline is value of last command to exit
#     with nonzero status, or zero if all commands succeeded.
#   - `-x`: Print trace of many of commands below; useful for debugging.
set -e -x -o pipefail

# Many executables in [viral-ngs](https://github.com/broadinstitute/viral-ngs)
# depend on executables in this miniconda/bin/, so we add it to PATH env var
# here.
#
# PRECONDITION: miniconda/bin/ must somehow be downloaded and unpackaged into
# execution env.
export PATH="$PATH:$HOME/miniconda/bin/"

# Log system resource statistics every 1m.
dstat -cmdn 60 &

function main() {
  dx cat "$resources" | tar zx -C /

  ###################################
  # Fetch and decompress Kraken db. #
  ###################################
  mkdir "./$kraken_db_prefix"

  # Db can be compressed by gzip or LZ4; choose decompressor based on file
  # extension.
  decompressor="zcat"
  if [[ "$kraken_db_name" == *.lz4 ]]; then
    decompressor="lz4 -d"
  fi

  dx cat "$kraken_db" | $decompressor | tar -C "./$kraken_db_prefix" -xvf -

  if [ $(find "./$kraken_db_prefix" -type f | cut -d / -f 2,3 | sort | uniq | wc -l) -eq "1" ]; then
    # If tarball has top-level dir, then move contents of that dir up one dir.
    mv ./${kraken_db_prefix}/$(find "./$kraken_db_prefix" -type f | cut -d / -f 3 | uniq)/* ./${kraken_db_prefix}
    find "./$kraken_db_prefix" -type f
  fi

  du -sh "./$kraken_db_prefix"

  ##################################
  # Fetch and decompress Krona db. #
  ##################################
  # TODO: Refactor (same as above for Kraken).
  mkdir "./$krona_taxonomy_db_prefix"

  # Db can be compressed by gzip or LZ4; choose decompressor based on file
  # extension.
  decompressor="zcat"
  if [[ "$krona_taxonomy_db_name" == *.lz4 ]]; then
    decompressor="lz4 -d"
  fi

  dx cat "$krona_taxonomy_db" | $decompressor | tar -C "./$krona_taxonomy_db_prefix" -xvf -

  if [ $(find "./$krona_taxonomy_db_prefix" -type f | cut -d / -f 2,3 | sort | uniq | wc -l) -eq "1" ]; then
    # If tarball has top-level dir, then move contents of that dir up one dir.
    mv ./${krona_taxonomy_db_prefix}/$(find "./$krona_taxonomy_db_prefix" -type f | cut -d / -f 3 | uniq)/* ./${krona_taxonomy_db_prefix}
    find "./$krona_taxonomy_db_prefix" -type f
  fi

  du -sh "./$krona_taxonomy_db_prefix"

  ##########################
  # Process input samples. #
  ##########################

  mkdir -p ~/scratch/

  for i in "${!mappings[@]}"; do
    # TODO: Consider streaming this into a Unix FIFO pipe (?). That being said,
    # our depleted .bam files are rather small (on order of MiB), so streaming
    # will not gain much.
    dx cat "${mappings[$i]}" > ~/scratch/"${mappings_name[$i]}"

    output_filename_prefix="${mappings_prefix[$i]%.cleaned}"
    output_root_dir=~/"out/outputs/$output_filename_prefix"
    mkdir -p "$output_root_dir"/

    # Use Kraken to classify taxonomic profile of sample.
    viral-ngs/metagenomics.py kraken \
                              ~/scratch/"${mappings_name[$i]}" \
                              "./$kraken_db_prefix" \
                              --outReads "$output_root_dir"/"$output_filename_prefix".kraken-classified.txt.gz \
                              --outReport "$output_root_dir"/"$output_filename_prefix".kraken-report.txt \
                              --numThreads `nproc`

    mkdir -p ~/scratch/delete_me/

    # Use Krona to visualize taxonomic profiling output from Kraken.
    viral-ngs/metagenomics.py krona \
                              "$output_root_dir"/"$output_filename_prefix".kraken-classified.txt.gz \
                              "./$krona_taxonomy_db_prefix" \
                              ~/scratch/delete_me/"$output_filename_prefix".krona-report.html \
                              --noRank
    cp ~/scratch/delete_me/"$output_filename_prefix".krona-report.html "$output_root_dir"/
    tar -cvf "$output_root_dir"/archive.tar ~/scratch/delete_me/*
    rm -rf ~/scratch/delete_me/
  done

  dx-upload-all-outputs --parallel
}
