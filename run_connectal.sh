#! /bin/sh

set -o errexit
set -o nounset
set -o xtrace

docker run --rm -v `realpath ../apt`:/etc/apt:ro -v $PWD:$PWD -w $PWD jameyhicks/connectal \
    bash -c "export BUILDCACHE_CACHEDIR=`realpath ./buildcache`; apt-get update; apt-get install -y strace python3-pip libelf-dev; pip3 install gevent ply; cd ./connectal-master/examples/leds/; make build.bluesim"

export BUILDCACHE_CACHEDIR=`realpath ../../../../buildcache`
$BUILDCACHE_CACHEDIR/buildcache make VPROC=ONECYCLE
