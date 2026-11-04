#!/bin/bash
#
# Unit test for firmware_version_uniform in ../modules/sdk_firmware.sh: every control
# node must answer with the same /etc/version, and one that does not answer holds it.
# Mocks cubectl and remote_run. Run: bash test_firmware_version_uniform.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_firmware.sh"
body="$(awk '/^firmware_version_uniform\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: firmware_version_uniform not extracted"; exit 1; }
eval "$body"

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
yes_if(){ "$@" && echo y || echo n; }

# --- mocks: HOSTS is the control list, VER_<host> what that node's /etc/version reads
HOSTS="c1 c2 c3"
cubectl(){ local h out=; for h in $HOSTS; do out+="{\"hostname\":\"$h\"},"; done; echo "[${out%,}]"; }
remote_run(){ local v="VER_$1"; echo "${!v:-}"; }

NEW=CUBE_3.2.0_20261102-0000_aaaaaaaa OLD=CUBE_3.1.20_20260922-0628_698d74b2

VER_c1=$NEW VER_c2=$NEW VER_c3=$NEW
chk "1 all on one firmware"    "$(yes_if firmware_version_uniform)" y
VER_c3=$OLD
chk "2 one still on the old"   "$(yes_if firmware_version_uniform)" n
VER_c3=
chk "3 one not answering"      "$(yes_if firmware_version_uniform)" n
HOSTS=
chk "4 no control list"        "$(yes_if firmware_version_uniform)" n

echo "PASS=$pass FAIL=$fail"
[ $fail -eq 0 ]
