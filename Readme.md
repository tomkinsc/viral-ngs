# dnanexus/viral-ngs

#### [Broad Institute viral genomics analysis pipelines](https://github.com/broadinstitute/viral-ngs) on DNAnexus

The pipelines are available for use on DNAnexus. Use this repo if you're interested in modifying them or peeking under the hood.

This repo contains the source code for applets implementing discrete stages of the pipelines, and python scripts in the root directory to build the applets and instantiate DNAnexus [workflows](https://wiki.dnanexus.com/UI/Workflows) using them. You'll need the [DNAnexus SDK](https://wiki.dnanexus.com/Command-Line-Client/Quickstart) installed and set up to run these scripts.

### Continuous integration

[![Build Status](https://travis-ci.org/dnanexus/viral-ngs.svg?branch=dnanexus)](https://travis-ci.org/dnanexus/viral-ngs)

Travis CI tests changes to this branch. The `.travis.yml` uses a [secure environment variable](http://docs.travis-ci.com/user/environment-variables/#Secure-Variables) to encode a DNAnexus auth token providing access to the [bi-viral-ngs CI](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/data/) project. Travis builds the applets & workflows and then executes the workflows on small test datasets. Supporting materials for these tests are staged in the bi-viral-ngs CI project, which is public on DNAnexus.

### Resources tarball

To minimize wheel reinvention, most of the applets directly use tools and wrapper scripts maintained in the [existing Broad codebase](https://github.com/broadinstitute/viral-ngs). To expedite deployment, the applets require a tarball containg a fully built/installed version of this codebase. This tarball is built by the `build_resources_tarball.py` script, which calls on the `viral-ngs-builder` applet to build the codebase within the DNAnexus execution environment. The file ID of the tarball can be provided to the workflow builder scripts (they also have defaults).

The [`dnanexus-resources-tarball`](https://github.com/dnanexus/viral-ngs/tree/dnanexus-resources-tarball) branch of this repository is a version of the Broad codebase with a modified `.travis.yml` to automatically build the resources tarball in the [bi-viral-ngs CI:/resources_tarball](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/data/resources_tarball) folder from the current revision of that branch. As a best practice, the resources tarball used in published workflow versions should come from this folder.

### Software licensing issues

The workflows use two semi-proprietary software packages: GATK and Novoalign. Published workflow versions require the user to upload GATK and Novoalign tarballs and provide them as workflow inputs. Because the bi-viral-ngs CI project is public, the Travis workflow tests use copies of these tarballs staged in a separate, private project, which the auth token is also empowered to use.
