#!/bin/bash
# Preflight on the node: cluster check all ok and host memory headroom. Warns without ssh access.
min=${MIN_HOST_MEM_GB:-16}
out=$("$(dirname "$0")/node-ssh.sh" "$1" 'hex_cli -c cluster -c check; awk "/^MemAvailable/ {print \"mem\", int(\$2/1048576)}" /proc/meminfo')
if [ -z "$out" ]; then echo "preflight WARN cluster check: skipped, no ssh to root@$1"; exit 0; fi
rc=0
mem=$(awk '$1 == "mem" {print $2}' <<<"$out")
check=$(grep -v '^mem ' <<<"$out")
bad=$(awk 'NR > 1 && $2 != "ok"' <<<"$check")
if [ -n "$bad" ]; then echo "preflight FAIL cluster check:"; echo "$bad"; rc=3
else echo "preflight OK   cluster check: $(($(wc -l <<<"$check") - 1)) service groups ok"; fi
if [ "${mem:-0}" -lt "$min" ]; then echo "preflight FAIL host memory available on $1: ${mem:-?} GB (need $min; MIN_HOST_MEM_GB= overrides)"; rc=3
else echo "preflight OK   host memory available on $1: $mem GB (need $min)"; fi
exit $rc
