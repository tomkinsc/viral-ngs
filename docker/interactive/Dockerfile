# Dockerfile for the https://github.com/broadinstitute/viral-ngs codebase
# Builds an image intended for interactive use. Example:
#   $ sudo docker run -it -v /path/to/my/data:/viral-ngs/data mlin/viral-ngs
#   # ./run_all_tests.sh
FROM ubuntu:precise
MAINTAINER Mike Lin <mlin@dnanexus.com>

# install apt packages
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-suggests --no-install-recommends less vim wget unzip git build-essential zlib1g-dev libncurses5-dev default-jre-headless python-dev python-pip python-numpy python-scipy cython

# deploy repo
RUN git clone https://github.com/broadinstitute/viral-ngs.git /viral-ngs
WORKDIR /viral-ngs

# pip packages except those installed by apt above
RUN pip install `cat requirements.txt | grep -iv numpy | grep -iv scipy | grep -iv Cython`

# run the unit tests, causing just-in-time installation of individual tools
ENV PYTHONIOENCODING UTF8
RUN ./run_all_tests.sh

