#!/bin/bash

main() {
    set -e -x -o pipefail
    # export PATH="$PATH:$HOME/miniconda/bin"

    # deploy proprietary software (needed for build, but excluded from the
    # resources tarball)
    mkdir gatk
    dx cat "$gatk_tarball" | tar jx -C gatk/
    wait $pid
    export GATK_PATH=/home/dnanexus/gatk

    # clone viral-ngs
    git clone -n "$git_url" viral-ngs
    cd viral-ngs
    git checkout "$git_commit"

    # get tags from upstream, to facilitate the best naming of the revision
    git remote add upstream https://github.com/broadinstitute/viral-ngs.git
    git fetch upstream

    # detect revision
    GIT_REVISION=$(git describe --long --tags --dirty --always)

    # we're done with the viral-ngs repo and can remove it
    cd ~
    rm -rf viral-ngs

    # record a manifest of the filesystem before doing anything further
    (find / -type f -o -type l 2> /dev/null || true) | sort > /tmp/fs-manifest.0

    # deploy dx-docker beta (TODO: eliminate once dx-docker is stable in production)
    git clone -b dx-docker-beta --recursive https://github.com/dnanexus/dx-toolkit.git /dx-docker-beta
    make -C /dx-docker-beta python dx-docker
    source /dx-docker-beta/environment

    # pull the viral-ngs docker image
    dx-docker pull -q broadinstitute/viral-ngs$viral_ngs_version
    ls -lhR /tmp/dx-docker-cache/
    # generate a script /usr/local/bin/viral-ngs to invoke the viral-ngs docker image
    # TODO: remove source and --entrypoint once related dx-docker beta issues are resolved
    echo "#!/bin/bash
source /dx-docker-beta/environment
dx-docker run -v \$(pwd):/user-data --entrypoint ./env_wrapper.sh broadinstitute/viral-ngs$viral_ngs_version $@" > /usr/local/bin/viral-ngs
    chmod +x /usr/local/bin/viral-ngs


    # local installation of viral-ngs; this will be made redundant once we finish
    # docker conversion.

    # we need to unset the PYTHONPATH for the conda env
    DX_PYTHON_PATH=$PYTHONPATH
    unset PYTHONPATH

    # Use the upstream easy deploy script to install viral-ngs
    # (including tools and dependencies)
    wget https://raw.githubusercontent.com/broadinstitute/viral-ngs/master/easy-deploy-script/easy-deploy-viral-ngs.sh
    chmod u+x easy-deploy-viral-ngs.sh
    ./easy-deploy-viral-ngs.sh setup

    # record a new filesystem manifest
    (find / -type f -o -type l 2> /dev/null || true) | sort > /tmp/fs-manifest.1

    # diff the two manifests to get a list of all new files and symlinks
    comm -1 -3 /tmp/fs-manifest.0 /tmp/fs-manifest.1 | \
      egrep -v "^/proc/" | egrep -v "^/sys/" | egrep -v "^/tmp/" | egrep -v "/\.git/" \
      > /tmp/resources-manifest.txt
    comm -1 -3 /tmp/fs-manifest.0 /tmp/fs-manifest.1 | \
      egrep "^/tmp/dx-docker-cache/" \
      >> /tmp/resources-manifest.txt

    # reset the PYTHONPATH for dx upload to work
    export PYTHONPATH=$DX_PYTHON_PATH

    # upload a tarball with the new files
    resources=`tar -c -v -z -T /tmp/resources-manifest.txt | \
               dx upload --brief -o "viral-ngs-${GIT_REVISION}.resources.tar.gz" -`

    dx-jobutil-add-output resources "$resources" --class=file
}
