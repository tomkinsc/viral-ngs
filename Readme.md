# dnanexus/viral-ngs

#### DNAnexus instantiations of [Broad Institute viral genomics analysis pipelines](https://github.com/broadinstitute/viral-ngs)

The pipelines are available for use on DNAnexus. (TODO link to public project & docs.) Use this repo if you're interested in modifying them or learning more about how they work.

This repo contains the source code for applets implementing discrete stages of the pipelines, and python scripts in the root directory to build the applets and instantiate DNAnexus [workflows](https://wiki.dnanexus.com/UI/Workflows) using them. You'll need the [DNAnexus SDK](https://wiki.dnanexus.com/Command-Line-Client/Quickstart) installed and set up to run these scripts.

### Continuous integration

[![Build Status](https://travis-ci.org/dnanexus/viral-ngs.svg?branch=dnanexus)](https://travis-ci.org/dnanexus/viral-ngs)

Travis CI tests changes to this branch. The `.travis.yml` uses a [secure environment variable](http://docs.travis-ci.com/user/environment-variables/#Secure-Variables) to encode a DNAnexus auth token providing access to the [bi-viral-ngs CI](https://platform.dnanexus.com/projects/BXBXK180x0z7x5kxq11p886f/data/) project. Travis builds the applets & workflows and then executes the workflows on small test datasets. Various supporting materials for these tests are staged in the bi-viral-ngs CI project. 

### Resources tarball

### Software licensing issues
