# dnanexus/viral-ngs

#### [broadinstitute/viral-ngs pipelines](https://github.com/broadinstitute/viral-ngs) on DNAnexus

**The pipelines are available for use on DNAnexus. [See the wiki](https://github.com/dnanexus/viral-ngs/wiki) for instructions on how to run them. The following information is for developers interested in peeking under the hood or modifying them.**

Here you'll find the source code for applets implementing individual pipeline stages, and python scripts in the root directory to build the applets and instantiate DNAnexus [workflows](https://wiki.dnanexus.com/UI/Workflows) using them. You'll need the [DNAnexus SDK](https://wiki.dnanexus.com/Command-Line-Client/Quickstart) installed and set up to run these scripts.

### Continuous integration

[![Build Status](https://travis-ci.org/dnanexus/viral-ngs.svg?branch=dnanexus)](https://travis-ci.org/dnanexus/viral-ngs)

Travis CI tests is automatically triggered upon changes to the repo. The `.travis.yml` uses a [secure environment variable](http://docs.travis-ci.com/user/environment-variables/#Secure-Variables) to encode a DNAnexus auth token providing access to the [bi-viral-ngs CI](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/data/) project.

Travis builds the applets & workflows and then executes the workflows on small test datasets (by executing `build_workflows.py --run-tests`). Supporting materials for these tests are stored in the bi-viral-ngs CI project, which is public on DNAnexus.

### Resources tarball

To minimize wheel reinvention, most of the applets directly use tools and wrapper scripts maintained in the [existing Broad codebase](https://github.com/broadinstitute/viral-ngs).

Therefore, the applets require a tarball containing a fully built/installed version of the broadinstitute/viral-ngs codebase to expedite deployment. This tarball is built by the `build_resources_tarball.py` script, which calls on the `viral-ngs-builder` applet to build the codebase within the DNAnexus execution environment.

The file ID of the built tarball can be provided to the workflow builder scripts (or provided directly as defaults in the applets' dxapp.json file, see below).

The [`dnanexus-resources-tarball`](https://github.com/dnanexus/viral-ngs/tree/dnanexus-resources-tarball) branch of this repository is a version of the Broad Institute codebase with a modified `.travis.yml` to automatically build the resources tarball in the [bi-viral-ngs CI:/resources_tarball](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/data/resources_tarball) folder from the current revision of that branch. As a best practice, the resources tarball used in published workflow versions should come from this folder.

To incorporate code changes from [upstream](https://github.com/broadinstitute/viral-ngs):

1. Rebase the `dnanexus-resources-tarball` branch (specifically, the commit modifying `.travis.yml` as described above) on top of the desired upstream revision/tag, and (force) push to GitHub:

```shell
cd path/to/this/fork/of/viral-ngs

# Navigate to the resource tarball branch
git checkout dnanexus-resources-tarball

# Fetch the upstream changes
git fetch upstream

# Rebase the dnanexus-resources-tarball to a target tag release
git rebase <v1.x.y>

# Resolve merge conflicts, if any
# Note, retain the .travis.yml file in the dnanexus-resources-tarball branch, unless
# there are good reasons to change it :p

# Force-push (-f is necessary due to rebase earlier) to the remote branch
git push -u origin dnanexus-resources-tarball -f
```

2. Upon push to the `dnanexus-resources-tarball` brunch, Travis CI will l(according to the `.travis.yml` file, fetch the file `build_resources_tarball.py` from the remote ***`master`*** branch of `dnanexus/viral-ngs` (yes this is a little confusing), and launch it in the Travis environment (by executing `python build_resources_tarball.py --reuse-builder $(git rev-parse HEAD)`.

3. In the DNAnexus project [bi-viral-ngs CI](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/monitor/), you should see a job named `viral-ngs-bulder <git-hash>` that is the result of the execution of the `build_resources_tarball.py` script (mispelling noted and intended). It makes use (by default) the `viral-ngs-builder` applet found in the [bi-viral-ngs CI:/resources_tarball](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/data/resources_tarball) folder, as resolved by name.

4. Occasionally, the upstream repo may change the way that dependencies are installed (e.g. using a different package manager), which necessitate changing the builder routine used by `viral-ngs-builder`, please see the section **Resource building FAQ** for more details.

5. Upon successful completion of the `viral-ngs-bulder <git-hash>` job, a new resource is generated and stored in the [bi-viral-ngs CI:/resources_tarball](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/data/resources_tarball) folder. Take note of its file ID.

6. On the `dnanexus` branch (or wip branches from it), find the `resources` input in `viral-ngs-human-depletion/dxapp.json`, `viral-ngs-fasta-fetcher/dxapp.json`,  `viral-ngs-demux-wrapper/dxapp.json` and `viral-ngs-taxonomic-profiling/dxapp.json` and change their default to the new tarball's file ID. (All the other workflow stages in the assembly workflow take the cue from default setting in `viral-ngs-human-depletion`.)

7. Ensure that updating the resource tarball did not break things by checking the Travis CI results of the updated branch.

### Resource Building FAQ

#### Updates to the resources building process / viral-ngs-builder
The viral-ngs-builder essentially echoes the installation process provided in the [upstream](https://github.com/broadinstitute/viral-ngs/tree/master/travis) travis scripts (`before_install.sh`, `install-conda.sh`, `install-tools.sh`, `test-unit.sh` and `test-long.sh`). The builder app should be changed to echo changes to these files to ensure the installation and tests are current to the latest upstream versions.

After making the appropriate changes to the `viral-ngs-builder` applet (which one should commit to `master`), rebuild the applet into the [bi-viral-ngs CI:/resources_tarball](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/data/resources_tarball), archiving the older version:

```shell
dx build viral-ngs-builder --destination "bi-viral-ngs CI:/resources_tarball/" -a
```

The newly built version will be automatically used in future resource building process (see section on **Resources tarball**).

#### Hard coded paths to viral-ngs installed tools
Several executable tools that are installed by the `viral-ngs` install process (see above) are used in their raw forms without `viral-ngs` wrapper. These tools include, but are not limited to `samtools` and `novoindex`.

These tools are typically resolved by hard-coded paths in the DNAnexus applet bash script (search, for example, *"samtools="* in this repo). Upstream changes to the installation/build process may cause these paths to drift and break execution of DNAnexus applet.

In these cases, be sure to update the hard coded path. The easiest way to do this is to ssh into a worker that has unpacked the `viral-ngs` resources tarball and perform a Unix `find`.

### Software licensing issues

The workflows use two semi-proprietary software packages: GATK and Novoalign. Published workflow versions require the user to upload GATK and Novoalign tarballs and provide them as workflow inputs. Because the bi-viral-ngs CI project is public, the Travis workflow tests use copies of these tarballs staged in a separate, private project, which the auth token is also empowered to use.
