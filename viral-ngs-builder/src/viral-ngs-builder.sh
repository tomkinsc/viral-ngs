#!/bin/bash

main() {
    set -e -x -o pipefail
    export PATH="$PATH:$HOME/miniconda/bin"

    # deploy proprietary software (needed for build, but excluded from the
    # resources tarball)
    dx cat "$novocraft_tarball" | tar zx & pid=$!
    mkdir gatk
    dx cat "$gatk_tarball" | tar jx -C gatk/
    wait $pid
    export NOVOALIGN_PATH=/home/dnanexus/novocraft
    export GATK_PATH=/home/dnanexus/gatk

    # record a manifest of the filesystem before doing anything further
    (find / -type f -o -type l 2> /dev/null || true) | sort > /tmp/fs-manifest.0

    # clone viral-ngs
    git clone -n "$git_url" viral-ngs
    cd viral-ngs
    git checkout "$git_commit"

    # get tags from upstream, to facilitate the best naming of the revision
    git remote add upstream https://github.com/broadinstitute/viral-ngs.git
    git fetch upstream

    # detect revision
    GIT_REVISION=$(git describe --long --tags --dirty --always)

    # installations from upstream:/travis/install-pip.sh
    pip install -r requirements.txt
    pip install mock==2.0.0

    # installations from upstream:/travis/install-conda.sh
    wget https://repo.continuum.io/miniconda/Miniconda-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p $HOME/miniconda
    user=$(whoami)
    chown -R $user $HOME/miniconda
    export PATH="$PATH:$HOME/miniconda/bin"
    hash -r
    conda config --set always_yes yes --set changeps1 no
    conda config --add channels bioconda
    conda config --add channels r
    conda update -q conda
    conda info -a

    # installations from upstream:/travis/install-tools.sh
    nosetests -v test.unit.test_tools

    # run upstream tests from upstream:/travis/tests-unit.sh
    nosetests -v \
    --logging-clear-handlers \
    --with-xunit --with-coverage \
    --cover-inclusive --cover-branches --cover-tests \
    --cover-package broad_utils,illumina,assembly,interhost,intrahost,metagenomics,ncbi,read_utils,reports,taxon_filter,tools,util \
    -w test/unit/

    # run upstream tests from upstream:/travis/tests-unit.sh
    nosetests -v \
    --logging-clear-handlers \
    --with-xunit --with-coverage \
    --cover-inclusive --cover-branches --cover-tests \
    --cover-package broad_utils,illumina,assembly,interhost,intrahost,metagenomics,ncbi,read_utils,reports,taxon_filter,tools,util \
    -w test/integration/

    # record a new filesystem manifest
    (find / -type f -o -type l 2> /dev/null || true) | sort > /tmp/fs-manifest.1

    # diff the two manifests to get a list of all new files and symlinks
    comm -1 -3 /tmp/fs-manifest.0 /tmp/fs-manifest.1 | \
      egrep -v "^/proc" | egrep -v "^/sys" | egrep -v "^/tmp" | egrep -v "/\.git/" \
      > /tmp/resources-manifest.txt

    # upload a tarball with the new files
    resources=`tar -c -v -z -T /tmp/resources-manifest.txt | \
               dx upload --brief -o "viral-ngs-${GIT_REVISION}.resources.tar.gz" -`

    dx-jobutil-add-output resources "$resources" --class=file
}
