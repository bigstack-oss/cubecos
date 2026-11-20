#!/bin/bash
#
# Unit test for os_manila_service_remove (../modules/sdk_os.sh), which cluster > remove_node and the
# manila health repair use: it deletes the host's row of every share backend (<host>@<backend>),
# matches the whole hostname, so cn1 does not take cn10's rows, and fails when the service list
# cannot be read (cubecos#107).
#
# Self-contained: extracts the functions and answers their openstack calls from fixtures, so
# it needs no node.
#   Run: bash test_manila_service_remove.sh   (exit 0 = pass)
#   SDK_OS_SH=<file> runs it against another copy of sdk_os.sh.
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SDK_OS_SH:-$DIR/../modules/sdk_os.sh}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

for f in os_manila_service_remove ; do
    body="$(awk "/^$f\(\)/{p=1} p{print} p&&/^}/{exit}" "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $f not extracted"; exit 1; }
    eval "$body"
done

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

OPENSTACK=os_stub
DOWN=n
os_stub() {
    [ "$DOWN" = n ] || return 1
    case "$*" in
        "share service list --binary manila-share -f value -c ID -c Host")
            printf '%s\n' "7 cn1@generic" "8 cn1@nfs1" "9 cn10@generic" "10 cc1@generic" ;;
        *) echo "$*" >> "$T/calls" ;;
    esac
}
mariadb_calls() { grep -o "id = '[0-9]*'" "$T/calls" | tr '\n' ';'; }
run() { : > "$T/calls"; "$@" > "$T/out" 2> "$T/err"; rc=$?; }
calls() { tr '\n' ';' < "$T/calls"; }

/usr/bin/mariadb() { echo "mariadb $*" >> "$T/calls"; }
run os_manila_service_remove cn1 manila-share
chk "the row of every backend of cn1, not cn10's" "$rc $(mariadb_calls)" "0 id = '7';id = '8';"

DOWN=y
for f in "os_manila_service_remove cn1 manila-share" ; do
    run $f
    chk "an API that cannot be read fails ${f%% *}" "$rc" "1"
done

echo "test_manila_service_remove: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
