# dnanexus/viral-ngs

#### [broadinstitute/viral-ngs pipelines](https://github.com/broadinstitute/viral-ngs) on DNAnexus

**The pipelines are available for use on DNAnexus. [See the wiki](https://github.com/dnanexus/viral-ngs/wiki) for instructions on how to run them. The following information is for developers interested in peeking under the hood or modifying them.**

Here you'll find the source code for applets implementing individual pipeline stages, and python scripts in the root directory to build the applets and instantiate DNAnexus [workflows](https://wiki.dnanexus.com/UI/Workflows) using them. You'll need the [DNAnexus SDK](https://wiki.dnanexus.com/Command-Line-Client/Quickstart) installed and set up to run these scripts.

### Continuous integration

[![Build Status](https://travis-ci.org/dnanexus/viral-ngs.svg?branch=dnanexus)](https://travis-ci.org/dnanexus/viral-ngs)

Travis CI tests is automatically triggered upon changes to the repo. The `.travis.yml` uses a [secure environment variable](http://docs.travis-ci.com/user/environment-variables/#Secure-Variables) to encode a DNAnexus auth token providing access to the [bi-viral-ngs CI](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/data/) project.

Travis builds the applets & workflows and then executes the workflows on small test datasets (by executing `build_workflows.py --run-tests`). Supporting materials for these tests are stored in the bi-viral-ngs CI project, which is public on DNAnexus.

### Resources tarball

To minimize wheel reinvention, most of the applets directly use tools and wrapper scripts maintained in the [existing Broad codebase](https://github.com/broadinstitute/viral-ngs) packaged in an [ACI](https://coreos.com/blog/app-container-and-docker.html) exported from [Docker Hub](https://hub.docker.com/r/broadinstitute/viral-ngs/).

A tarball containing the ACI is built by the `viral-ngs-builder` applet in the DNAnexus execution environment. The `build_resources_tarball.py` helper script runs this applet and deposits the resources tarball in the [bi-viral-ngs CI:/resources_tarball](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/data/resources_tarball) folder. The file ID of the built tarball can be provided to the workflow builder scripts (or provided directly as defaults in the applets' dxapp.json file, see below).

To incorporate a new image from Docker Hub:

1. `./build_resources_tarball.py [:TAG|@DIGEST]` to launch `viral-ngs-builder` in the [bi-viral-ngs CI](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/monitor/) DNAnexus project.

2. Upon successful completion of the `viral-ngs-builder` job, a new resource is generated and stored in the [bi-viral-ngs CI:/resources_tarball](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/data/resources_tarball) folder. Take note of its file ID.

3. On the `dnanexus` branch (or wip branches from it), find the `resources` input in `viral-ngs-human-depletion/dxapp.json`, `viral-ngs-fasta-fetcher/dxapp.json`,  `viral-ngs-demux-wrapper/dxapp.json` and `viral-ngs-taxonomic-profiling/dxapp.json` and change their default to the new tarball's file ID. (All the other workflow stages in the assembly workflow take the cue from default setting in `viral-ngs-human-depletion`.) `find . -name dxapp.json | xargs -i sed -i s/OLD_FILE_ID/NEW_FILE_ID/ {}`

4. Ensure that updating the resource tarball did not break things by checking the Travis CI results of the updated branch.

### Software licensing issues

The workflows use two semi-proprietary software packages: GATK and Novoalign. Published workflow versions require the user to upload GATK tarball and Novoalign license and provide them as workflow inputs. 

Because the bi-viral-ngs CI project is public, the Travis workflow tests use copies of these staged in a separate, private project, which the auth token is also empowered to use.


