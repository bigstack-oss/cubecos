#!/bin/bash
set -e

SCRIPT_DIR=$(dirname $0)
pushd $SCRIPT_DIR

echo $SCRIPT_DIR

./download
./build
./package-cli

popd