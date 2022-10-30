#! /bin/sh

set -o errexit
set -o nounset
set -o xtrace

WORK_DIR=$PWD
BSC_TGZ=bsc.tgz
BSC_DIR=bsc

# Install Connectal dependencies
pip3 install gevent ply

# Download Connectal
git clone --depth 1 https://github.com/cambridgehackers/connectal.git

# Download BSC
wget -O $BSC_TGZ https://github.com/B-Lang-org/bsc/releases/download/2022.01/bsc-2022.01-ubuntu-20.04.tar.gz
tar zxf $BSC_TGZ

# Remove the original top folder and extract into the folder $BSC_DIR
tar zxf $BSC_TGZ --strip-components=1 --one-top-level=$BSC_DIR

BSC_HOME=`realpath $BSC_DIR`
export BLUESPECDIR=$BSC_HOME/lib
export PATH="$PATH:$BSC_HOME/bin:$BDW_HOME/bin"

# Download bsc-contrib
git clone --depth 1 https://github.com/B-Lang-org/bsc-contrib.git
cd bsc-contrib
make PREFIX=$BSC_HOME install

cd $WORK_DIR/audio/connectal
make simulation run_simulation

cd $WORK_DIR/riscv/connectal
make simulation run_simulation
