#
# RIOT toolchain builder Dockerfile
#

FROM ubuntu:bionic

LABEL maintainer="Kaspar Schleiser <kaspar@riot-os.org>"

ENV DEBIAN_FRONTEND noninteractive

ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8

RUN \
    echo 'Update the package index files to latest available versions' >&2 && \
    apt-get update && \
    apt-get -y --no-install-recommends install \
        build-essential \
        libgmp-dev \
        libmpc-dev \
        libmpfr-dev \
        libz-dev \
        texinfo \
        wget

# Create working directory for mounting the sources
RUN mkdir -m 777 -p /build

# By default, run a shell when no command is specified on the docker command line
CMD ["/bin/bash"]

WORKDIR /build
