#!/bin/bash

main() {
    set -e -x -o pipefail

    # record a manifest of the filesystem before doing anything further
    (find / -type f -o -type l 2> /dev/null || true) | sort > /tmp/fs-manifest.0

    # deploy dx-docker beta (TODO: eliminate once dx-docker is stable in production)
    git clone -b dx-docker-beta --recursive https://github.com/dnanexus/dx-toolkit.git /dx-docker-beta
    make -C /dx-docker-beta python dx-docker
    rm -rf /dx-docker-beta/.git*
    source /dx-docker-beta/environment

    # pull the viral-ngs docker image
    dx-docker pull -q broadinstitute/viral-ngs$viral_ngs_version
    ls -lhR /tmp/dx-docker-cache/
    # generate a script /usr/local/bin/viral-ngs to invoke the viral-ngs docker image
    # TODO: remove source and --entrypoint once related dx-docker beta issues are resolved
    echo "#!/bin/bash
source /dx-docker-beta/environment
set -x
dx-docker run -v \$(pwd):/user-data --entrypoint ./env_wrapper.sh broadinstitute/viral-ngs$viral_ngs_version \"\$@\"" > /usr/local/bin/viral-ngs
    chmod +x /usr/local/bin/viral-ngs

    # record a new filesystem manifest
    (find / -type f -o -type l 2> /dev/null || true) | sort > /tmp/fs-manifest.1

    # diff the two manifests to get a list of all new files and symlinks
    comm -1 -3 /tmp/fs-manifest.0 /tmp/fs-manifest.1 | \
      egrep -v "^/proc/" | egrep -v "^/sys/" | egrep -v "^/tmp/" | egrep -v "/\.git/" \
      > /tmp/resources-manifest.txt
    comm -1 -3 /tmp/fs-manifest.0 /tmp/fs-manifest.1 | \
      egrep "^/tmp/dx-docker-cache/" \
      >> /tmp/resources-manifest.txt

    # upload a tarball with the new files
    rinsed_version=$(echo "$viral_ngs_version" | tr -d ":@")
    resources=`tar -c -v -z -T /tmp/resources-manifest.txt | \
               dx upload --brief -o "viral-ngs-${rinsed_version}.resources.tar.gz" -`

    dx-jobutil-add-output resources "$resources" --class=file
}
