#!/bin/bash
# Run $2 on root@$1: ROOT_PASS (default Cube@<last two octets of $1>, the set_ready default), then key login.
target=$1 cmd=$2
ssho=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR)
IFS=. read -r _ _ o3 o4 <<<"$target"
SSHPASS=${ROOT_PASS:-Cube@$o3.$o4} sshpass -e ssh "${ssho[@]}" root@"$target" "$cmd" 2>/dev/null ||
    ssh "${ssho[@]}" -o BatchMode=yes root@"$target" "$cmd" 2>/dev/null
