#!/bin/bash
#
# Unit test for ../modules/sdk_gpu.sh:
#   gpu_resource_type_list -- the resource type picker feed for
#                            `hex_cli -c gpu resource_set` (#1538); offers the
#                            card's supportTypes and nothing else
#
# CliMatchCmdDescHelper pairs the plain and the VERBOSE=1 output line by line,
# so both forms must list the same types in the same order.
#
# Self-contained: extracts the function under test and stubs gpu_device_list.
#   Run: bash test_gpu_resource_type_list.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_SRC="$DIR/../modules/sdk_gpu.sh"
for fn in gpu_resource_type_list ; do
    eval "$(awk -v f="^$fn\\\\(\\\\)" '$0 ~ f{p=1} p{print} p&&/^}/{exit}' "$GPU_SRC")"
    [ "$(type -t $fn)" = function ] || { echo "FAIL: $fn not extracted"; exit 1; }
done

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

list() { eval "gpu_device_list() { $1 }"; }
plain() { VERBOSE=0 gpu_resource_type_list "$1" 2>/dev/null | tr '\n' ' '; }
verbose() { VERBOSE=1 gpu_resource_type_list "$1" 2>/dev/null | cut -d' ' -f1 | tr '\n' ' '; }
rc() { VERBOSE=0 gpu_resource_type_list "$1" >/dev/null 2>&1; echo $?; }

TWO='{"id":"GPU-b","type":"pgpu","supportTypes":["pgpu","sriovVgpu"]}'
ALL='{"id":"GPU-c","type":"sriovVgpu","supportTypes":["pgpu","sriovVgpu","migBackedVgpu"]}'
list "echo '[{\"id\":\"GPU-a\",\"type\":\"pgpu\",\"supportTypes\":[\"pgpu\"]},$TWO,$ALL,{\"id\":\"GPU-d\",\"type\":\"pgpu\"}]';"

ck "$(plain GPU-a)" "pgpu " "passthrough-only card -> pgpu alone"
ck "$(plain GPU-b)" "pgpu sriovVgpu " "card without MIG -> migBackedVgpu is not offered"
ck "$(plain GPU-c)" "pgpu sriovVgpu migBackedVgpu " "card that supports all three -> all three"
ck "$(rc GPU-b)" "0" "a described card -> success"

# VERBOSE=1 has to pair up with the plain form row for row, starting each row
# with the type it describes.
ck "$(verbose GPU-b)" "$(plain GPU-b)" "verbose rows pair with the plain rows"
ck "$(verbose GPU-c)" "$(plain GPU-c)" "verbose rows pair with the plain rows (all three)"
ck "$(VERBOSE=1 gpu_resource_type_list GPU-b | wc -l | tr -d ' ')" "2" "verbose emits one row per type"

# Every answer it cannot give is a failure with nothing on stdout, never an
# empty picker.
ck "$(rc GPU-d)" "1" "card with no supportTypes -> failure"
ck "$(plain GPU-d)" "" "card with no supportTypes -> nothing on stdout"
ck "$(rc GPU-x)" "1" "card absent from the list -> failure"
ck "$(plain GPU-x)" "" "card absent from the list -> nothing on stdout"

list 'echo "malformed" >&2; return 1;'
ck "$(rc GPU-a)" "1" "gpu_device_list failing -> failure"
ck "$(plain GPU-a)" "" "gpu_device_list failing -> nothing on stdout"

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
