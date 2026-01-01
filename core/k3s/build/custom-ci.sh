#!/bin/bash
set -e

SCRIPT_DIR=$(dirname $0)
pushd $SCRIPT_DIR

echo $SCRIPT_DIR

# cd $(dirname $0)/..
./download
./build

popd