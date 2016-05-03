#!/bin/bash
#

# The following line causes bash to exit at any point if there is any error
# and to output each line as it is executed -- useful for debugging
set -e -x -o pipefail

export PATH="$PATH:$HOME/miniconda/bin/"
dx cat "$resources" | tar zx -C /

# log detailed sys utilization
dstat -cmdn 60 &

#
# Fetch and uncompress database
#
mkdir "./$database_prefix"
db_decompressor="zcat"
if [[ "$database_name" == *.lz4 ]]; then
	db_decompressor="lz4 -d"
fi
dx cat "$database" | $db_decompressor | tar -C "./$database_prefix" -xvf -
# if the tarball had a top-level directory component, move the contents up.
if [ $(find "./$database_prefix" -type f | cut -d / -f 2,3 | sort | uniq | wc -l) -eq "1" ]; then
	mv ./${database_prefix}/$(find "./$database_prefix" -type f | cut -d / -f 3 | uniq)/* ./${database_prefix}
	find "./$database_prefix" -type f
fi
du -sh "./$database_prefix"

#
# Run Kraken
#
mkdir -p ~/input/
mkdir -p ~/out/classified/ ~/out/report/ ~/out/html/

for i in "${!reads[@]}"; do
  dx cat "${reads[$i]}" > ~/input/"${reads_prefix[$i]}".bam
  viral-ngs/metagenomics.py kraken ~/input/"${reads_prefix[$i]}".bam "./$database_prefix" --outReads ~/out/classified/"${reads_prefix[$i]}".kraken-classified.txt.gz --outReport ~/out/report/"${reads_prefix[$i]}".kraken-report.txt --numThreads `nproc`

  # viral-ngs/metagenomics.py krona ~/out/classified/"${reads_prefix[$i]}".kraken-classified.txt.gz ~/out/html/"${reads_prefix[$i]}".report.html --noRank
done

#
# Upload results
#
dx-upload-all-outputs --parallel
