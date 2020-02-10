#!/bin/bash

if [ -z "${1}" ]; then
    usage
    exit 1
fi

TARGET=$1
shift

PATCHDIR=$(pwd)/patches

# mirror for binutils, gcc and gdb
: ${GNU_MIRROR:=http://ftp.gnu.org/gnu}

#
GCC_VER=9.2.0
GCC_SHA256=ea6ef08f121239da5695f76c9b33637a118dcf63e24164422231917fa61fb206
GCC_MIRROR=${GNU_MIRROR}/gcc/gcc-${GCC_VER}

BINUTILS_VER=2.34
BINUTILS_SHA256=f00b0e8803dc9bab1e2165bd568528135be734df3fabf8d0161828cd56028952
BINUTILS_MIRROR=${GNU_MIRROR}/binutils

NEWLIB_VER=3.3.0
NEWLIB_SHA256=58dd9e3eaedf519360d92d84205c3deef0b3fc286685d1c562e245914ef72c66
NEWLIB_MIRROR=https://sourceware.org/pub/newlib

GDB_VER=9.1
GDB_SHA256=699e0ec832fdd2f21c8266171ea5bf44024bd05164fdf064e4d10cc4cf0d1737
GDB_MIRROR=${GNU_MIRROR}/gdb

# package version number. travis sets ${GCC_VER}-${TRAVIS_BUILD_NUMBER}.
: ${PKG_VER:=${GCC_VER}}

# base directory to install compiled binaries into
: ${RT_INSTALL_PREFIX:=${HOME}/opt/riot-toolchain}

# directory to download source files and store intermediates
: ${RT_TMP_DIR:=~/tmp}
: ${RT_BUILDDIR:=${RT_TMP_DIR}/riot-toolchain-build/${TARGET}}

RT_INSTALL_DIR=${RT_INSTALL_PREFIX}/${TARGET}/${PKG_VER}

# uncomment to support multi-threaded compile
: ${MAKEFLAGS:=-j4}
export MAKEFLAGS

DOWNLOADER=wget
DOWNLOADER_OPTS="--progress=dot:giga -c"

SPACE_NEEDED=2641052
FREETMP=`df ${RT_TMP_DIR} | awk '{ if (NR == 2) print $4}'`

FILES=.

if [ `uname` = "Linux" ]; then
  SHA256=sha256sum
  SHA256_OPTS="-c -"
elif [ `uname` = "Darwin" ]; then
  SHA256=sha256
  SHA256_OPTS=""
else
    echo "CAUTION: No 'sha256' tool for your host system found!"
fi

# set target specific options
case $TARGET in
  msp430-elf)
    ;;
#  arm-none-eabi)
#    ;;
  *)
    echo "$0: unsupported target $TARGET."
    exit 1
esac

build_binutils() {
    echo "Building binutils..."
    if [ ! -e binutils-${BINUTILS_VER}/.binutils_extracted ] ; then
        rm -rf binutils-${BINUTILS_VER}
        tar -xaf ${FILES}/binutils-${BINUTILS_VER}.tar.xz
        touch binutils-${BINUTILS_VER}/.binutils_extracted
    fi
    rm -rf binutils-build && mkdir -p binutils-build && cd binutils-build
    ../binutils-${BINUTILS_VER}/configure \
      --target=${TARGET} \
      --prefix=${RT_INSTALL_DIR} \
      --enable-interwork \
      --enable-multilib \
      --enable-lto \
      --enable-gold \
      --enable-plugins
    make all CFLAGS="${CFLAGS}"
    make install
    cd ${RT_BUILDDIR}
}

build_gcc() {
    echo "Building gcc..."
    if [ ! -e gcc-${GCC_VER}/.gcc_extracted ] ; then
        rm -Rf gcc-${GCC_VER}
        tar -xaf ${FILES}/gcc-${GCC_VER}.tar.xz
        ( cd gcc-${GCC_VER} && patch -p1 < ${PATCHDIR}/gcc-use-init_array-if-needed.patch )
        touch gcc-${GCC_VER}/.gcc_extracted
    fi
    rm -rf gcc-build && mkdir -p gcc-build && cd gcc-build

    export CFLAGS_FOR_TARGET="-g -gdwarf-2 -Os -ffunction-sections -fdata-sections"
    export CXXFLAGS_FOR_TARGET="-g -gdwarf-2 -Os -ffunction-sections -fdata-sections"

    ../gcc-${GCC_VER}/configure \
    --prefix=${RT_INSTALL_DIR} \
    --target=${TARGET} \
    --disable-decimal-float \
    --disable-libffi \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libstdcxx-pch \
    --disable-nls \
    --disable-shared \
    --disable-tls \
    --enable-addons \
    --enable-gnu-indirect-function \
    --enable-interwork \
    --enable-languages=c,c++ \
    --enable-lto \
    --enable-multilib \
    --enable-plugins \
    --with-newlib \
    --with-system-zlib \
    --with-sysroot=${RT_INSTALL_DIR} \
    ${GCC_ARGS_EXTRA}

    make all-gcc all-target-libgcc #all-target-libstdc++-v3
    make install-strip-gcc install-target-libgcc #install-target-libstdc++-v3

    cd ${RT_BUILDDIR}
}

extract_newlib() {
    if [ ! -e newlib-${NEWLIB_VER}/.newlib_extracted ] ; then
        echo -n "Extracting newlib..."
        rm -Rf newlib-${NEWLIB_VER}
        tar -xaf ${FILES}/newlib-${NEWLIB_VER}.tar.gz
        ( cd newlib-${NEWLIB_VER} && patch -p1 < ${PATCHDIR}/newlib-syscalls.patch )
        touch newlib-${NEWLIB_VER}/.newlib_extracted
        echo " Done."
    fi
}

build_newlib() {
    cd ${RT_BUILDDIR} &&

    if [ ! -e .newlib_extracted ] ; then
        extract_newlib
    fi

    rm -rf newlib-build && mkdir -p newlib-build && cd newlib-build

    export AR_FOR_TARGET="${RT_INSTALL_DIR}/bin/${TARGET}-gcc-ar"
    export NM_FOR_TARGET="${RT_INSTALL_DIR}/bin/${TARGET}-gcc-nm"
    export RANLIB_FOR_TARGET="${RT_INSTALL_DIR}/bin/${TARGET}-gcc-ranlib"
    export CFLAGS_FOR_TARGET="-gdwarf-2"
      ../newlib-${NEWLIB_VER}/configure \
        --target=${TARGET} \
        --prefix=${RT_INSTALL_DIR} \
        --disable-newlib-fseek-optimization \
        --disable-newlib-io-float \
        --disable-newlib-supplied-syscalls \
        --disable-newlib-unbuf-stream-opt \
        --disable-newlib-wide-orient \
        --disable-nls \
        --disable-threads \
        --enable-interwork \
        --enable-lite-exit \
        --enable-lto \
        --enable-multilib \
        --enable-newlib-global-atexit \
        --enable-newlib-nano-formatted-io \
        --enable-newlib-nano-malloc \
        --enable-newlib-reent-small \
        --enable-target-optspace

    make all
    make install

    cd ${RT_BUILDDIR}
}

build_gdb() {
    echo "Building gdb..."
    if [ ! -e .gdb_extracted ] ; then
        tar -xaf ${FILES}/gdb-${GDB_VER}.tar.xz
        touch .gdb_extracted
    fi
    rm -rf gdb-build && mkdir -p gdb-build && cd gdb-build
    ../gdb-${GDB_VER}/configure \
      --target=${TARGET} \
      --prefix=${RT_INSTALL_DIR} \
      --enable-interwork \
      --enable-multilib \
      --disable-build-docs

    make all CFLAGS="-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"
    make install-strip-gdb

    cd ${RT_BUILDDIR}
}

clean() {
    echo "Cleaning up..."
    rm -rf .gdb_extracted .newlib_extracted .gcc_extracted .binutils_extracted
    rm -rf binutils-build gcc-build newlib-build gdb-build
}

export PATH=$PATH:${RT_INSTALL_DIR}/bin

download() {
    download_file ${BINUTILS_MIRROR} binutils-${BINUTILS_VER}.tar.xz ${BINUTILS_SHA256}
    download_file ${GCC_MIRROR} gcc-${GCC_VER}.tar.xz ${GCC_SHA256}
    download_file ${NEWLIB_MIRROR} newlib-${NEWLIB_VER}.tar.gz ${NEWLIB_SHA256}
    download_file ${GDB_MIRROR} gdb-${GDB_VER}.tar.xz ${GDB_SHA256}
}

download_file() {
    echo "Downloading ${1}/${2}..."
    ${DOWNLOADER} ${DOWNLOADER_OPTS} $1/$2

    echo -n "Checking SHA256 of "
    echo "${3}  ${2}" | ${SHA256} ${SHA256_OPTS}
}

check_space() {
    echo "Checking disk space in ${RT_TMP_DIR}"
    if [ $FREETMP -lt $SPACE_NEEDED ]
    then
        echo "Not enough available space in ${RT_TMP_DIR}. Minimum ${SPACE_NEEDED} free bytes required."
        exit 1
    fi
}

build_all() {
    echo "Starting in ${RT_BUILDDIR}. Installing to ${RT_INSTALL_DIR}."
    check_space
    download
    build_binutils
    extract_newlib
    build_gcc
    build_newlib
    build_gdb

    echo "Build complete."
}

usage() {
    echo "usage: ${0} <arm|msp430> build_[binutils|gcc|newlib|gdb|all]"
    echo "example: ./build build_all"
    echo ""
    echo "Builds a GNU GCC toolchain for RIOT. installs to ${RT_INSTALL_DIR}, uses ${RT_BUILDDIR} as temp."
    echo "Edit to change these directories."
    echo "Run like \"MAKEFLAGS=-j4${0} build_all\" to speed up on multicore systems."
}

# Fail on any error
set -e

mkdir -p ${RT_BUILDDIR}

cd ${RT_BUILDDIR}

$*
