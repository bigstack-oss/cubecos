#!/bin/bash
#
# Unit test for ../modules/sdk_fixpack.sh: each node's installed fixpacks come
# from its own history, missing/status report per node, and rollback only
# touches nodes whose latest fixpack is the one being rolled back.
#
# Self-contained: sources the module with hex_config/remote_run/HEX_SDK mocked, so it
# needs no cluster.  Run: bash test_fixpack_status.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROG=test
Error(){ echo "Error $*" >&2 ; exit 1 ; }
. "$DIR/../modules/sdk_fixpack.sh"

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# history as `hex_config fixpack_get_history` prints it, per node
declare -A HIST
HIST[n1]='01 Jan 2026 00:00:00|v3.1.0-001|a|Yes|Installed|d|1
02 Jan 2026 00:00:00|v3.1.0-002|b|Yes|Installed|d|2'
HIST[n2]='01 Jan 2026 00:00:00|v3.1.0-001|a|Yes|Installed|d|1
02 Jan 2026 00:00:00|v3.1.0-002|b|Yes|Installed|d|2
03 Jan 2026 00:00:00|v3.1.0-002|b|No|Uninstalled|d|3'
HIST[n3]=''
NODE=n1
HOSTNAME=n1
CUBE_NODE_LIST_HOSTNAMES=(n1 n2 n3)
ROLLED=
/usr/sbin/hex_config(){ [ "$1" = fixpack_rollback ] && echo "rolled back $NODE" ; }
hex_config_mock(){ [ -n "${HIST[$NODE]}" ] && echo "${HIST[$NODE]}" ; }
# route the module's hex_config call to the mock for $NODE
fixpack_installed_orig=$(declare -f fixpack_installed | sed 's#/usr/sbin/hex_config fixpack_get_history#hex_config_mock#')
eval "$fixpack_installed_orig"
HEX_SDK=_hexsdk
# a local call runs as $HOSTNAME; one inside remote_run keeps the remote NODE
_hexsdk(){ local f=$1 ; shift ; [ -n "${IN_REMOTE:-}" ] || NODE=$HOSTNAME
    case $f in fixpack_id) echo v3.1.0-002 ;; *) $f "$@" ;; esac ; }
UNREACH=
is_sshable(){ [ "x$1" != "x$UNREACH" ] ; }
# like the real one: Error (exit) when the node isn't sshable
remote_run(){ is_sshable $1 || Error "$1 not sshable" ; ( NODE=$1 ; shift ; IN_REMOTE=1 ; eval "$*" ) ; }

# 1. latest action per id wins
IN_REMOTE=1
NODE=n1 ; chk "1 n1 installed"   "$(fixpack_installed | tr '\n' ' ')" "v3.1.0-001 v3.1.0-002 "
NODE=n2 ; chk "1 n2 rolled back" "$(fixpack_installed | tr '\n' ' ')" "v3.1.0-001 "
NODE=n3 ; chk "1 n3 none"        "$(fixpack_installed)"               ""
IN_REMOTE=

# 2. missing nodes for v3.1.0-002
NODE=n1 ; chk "2 missing" "$(fixpack_missing_nodes x.fixpack | tr '\n' ' ')" "n2 n3 "

# 3. status against every id installed anywhere
NODE=n1 ; out=$(fixpack_status) ; r=$?
chk "3 n1 ok"      "$(echo "$out" | grep '^n1|')" "n1|v3.1.0-001 v3.1.0-002|ok"
chk "3 n2 missing" "$(echo "$out" | grep '^n2|')" "n2|v3.1.0-001|missing v3.1.0-002"
chk "3 n3 missing" "$(echo "$out" | grep '^n3|')" "n3|-|missing v3.1.0-001 v3.1.0-002"
chk "3 fails"      "$r" "1"

# 4. status for one id, with a node unreachable
NODE=n1 ; UNREACH=n3 ; out=$(fixpack_status v3.1.0-001) ; UNREACH=
chk "4 n2 ok"          "$(echo "$out" | grep '^n2|')" "n2|v3.1.0-001|ok"
chk "4 n3 unreachable" "$(echo "$out" | grep '^n3|')" "n3|-|unreachable"

# 5. all installed -> ok, exit 0
HIST[n2]=${HIST[n1]} ; HIST[n3]=${HIST[n1]}
NODE=n1 ; fixpack_status >/dev/null ; chk "5 all ok" "$?" "0"
NODE=n1 ; chk "5 none missing" "$(fixpack_missing_nodes x.fixpack)" ""

# 6. rollback point: read from fixpack-0/fixpack.info
FIXPACK_ROLLBACK_DIR=$(mktemp -d)
chk "6 no rollback point" "$(fixpack_rollback_top)" ""
mkdir -p $FIXPACK_ROLLBACK_DIR/fixpack-0
echo 'FIXPACK_ID="v3.1.0-002"' > $FIXPACK_ROLLBACK_DIR/fixpack-0/fixpack.info
chk "6 latest rollback point" "$(fixpack_rollback_top)" "v3.1.0-002"
rm -rf $FIXPACK_ROLLBACK_DIR

# 7. per-node latest rollback points: n1/n2 on -002, n3 on -001
declare -A TOP=([n1]=v3.1.0-002 [n2]=v3.1.0-002 [n3]=v3.1.0-001)
fixpack_rollback_top(){ echo ${TOP[$NODE]:-} ; }
chk "7 id is the local one"   "$(fixpack_rollback_id)" "v3.1.0-002"
chk "7 nodes on that id"      "$(fixpack_rollback_nodes v3.1.0-002 | tr '\n' ' ')" "n1 n2 "
chk "7 local rollback"        "$(fixpack_node_rollback n1 v3.1.0-002)" "rolled back n1"
chk "7 remote rollback"       "$(fixpack_node_rollback n2 v3.1.0-002)" "rolled back n2"
out=$(fixpack_node_rollback n3 v3.1.0-002 2>&1) ; r=$?
chk "7 refuses other latest"  "$r" "1"
chk "7 says why"              "$(echo "$out" | grep -c 'latest fixpack is v3.1.0-001')" "1"
TOP[n1]= ; chk "7 falls back to a peer's" "$(fixpack_rollback_id)" "v3.1.0-002"
TOP=() ; chk "7 none anywhere" "$(fixpack_rollback_id)" ""

echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: fixpack status" ; exit 0 ; } || exit 1
