#!/bin/bash
#
# ceph_mirror_peer_vip / ceph_mirror_daemon_restart / ceph_mirror_promoted_instance_list:
# a peer name with '-', the daemon start limit, and both openstackclient server json shapes.
#
#   Run: bash test_ceph_mirror.sh
#
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_ceph.sh
for fn in ceph_mirror_peer_vip ceph_mirror_daemon_restart ceph_mirror_promoted_instance_list ; do
    sed -n "/^$fn()/,/^}/p" $SRC >> $T/fn.sh
done
source $T/fn.sh

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-46s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-46s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

# --- peer vip: the local site is a symlink, the peer a regular file ---
site(){ rm -rf $T/ceph ; mkdir -p $T/ceph ; touch $T/ceph/ceph.conf ; ln -s $T/ceph/ceph.conf $T/ceph/$1-site.conf ; touch $T/ceph/$2-site.conf ; }
site cube4510-10.32.45.10 cube-combined-10.32.1.200
chk "peer name with '-'"                      "$(ceph_mirror_peer_vip $T/ceph)" "10.32.1.200"
site cube-combined-10.32.1.200 cube4510-10.32.45.10
chk "peer name without '-'"                   "$(ceph_mirror_peer_vip $T/ceph)" "10.32.45.10"
site my-dr-site-1-10.0.0.5 a-b-c-192.168.10.250
chk "several '-' and digits in the name"      "$(ceph_mirror_peer_vip $T/ceph)" "192.168.10.250"
rm -rf $T/ceph ; mkdir -p $T/ceph
chk "unpaired"                                "$(ceph_mirror_peer_vip $T/ceph)" ""

# --- daemon restart clears the start limit first ---
cmd(){ shift ; echo "$*" >> $T/cmd.log ; }
: > $T/cmd.log
ceph_mirror_daemon_restart cube4510-10.32.45.10-site
chk "reset-failed before restart"             "$(paste -sd'|' $T/cmd.log)" \
    "systemctl reset-failed ceph-rbd-mirror@cube4510-10.32.45.10-site.service|systemctl restart ceph-rbd-mirror@cube4510-10.32.45.10-site.service"

# --- promoted instances: both server json shapes ---
BUILTIN_BACKPOOL=cinder-volumes
Quiet(){ "$@" >/dev/null 2>&1 ; }
rbd(){ # rbd info <pool>/<img> [--format json]
    local img=${2#*/}
    [ -e $T/rbd/$img ] || return 1
    [ "$3" = "--format" ] && echo "{\"mirroring\":{\"primary\":$(cat $T/rbd/$img)}}"
    return 0
}
mirror_dir_run(){ eval "$(declare -f ceph_mirror_promoted_instance_list | sed "s|/var/lib/ceph/rbd-mirror|$T/srv|")" ; VERBOSE=1 ceph_mirror_promoted_instance_list ; }
mkdir -p $T/srv $T/rbd
cat > $T/srv/vm-new <<'J'
{"name":"vm-new","project_name":"admin","flavor":{"name":"t2.nano","vcpus":1},"addresses":{"net1":["10.0.0.9"]},"volumes_attached":[{"id":"b1"},{"id":"d1"}]}
J
cat > $T/srv/vm-old <<'J'
{"name":"vm-old","project_name":"admin","flavor":"t2.small (abc)","addresses":{"net1":["10.0.0.8"]},"attached_volumes":[{"id":"b2"}]}
J
echo true > $T/rbd/volume-b1 ; echo false > $T/rbd/volume-d1 ; echo true > $T/rbd/volume-b2
chk "osc 7 json, one volume not promoted"     "$(mirror_dir_run | grep -c vm-new)" "0"
chk "older json, all promoted"                "$(mirror_dir_run | grep vm-old)" "vm-old,admin,t2.small,net1,b2"
echo true > $T/rbd/volume-d1
chk "osc 7 json, all promoted"                "$(mirror_dir_run | grep vm-new)" "vm-new,admin,t2.nano,net1,b1 d1"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
