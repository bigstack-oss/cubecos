#!/bin/bash
#
# Unit test for health_ceph_mds_check in ../modules/sdk_health.sh (cubecos#2204).
#
# The check asks every node `mountpoint -- /mnt/cephfs` through cmd. On a hung cephfs
# mount that stat waits in the kernel until killed, and cmd bounds only the ssh, at
# 600s, so one hung node held the check, and cluster check's Storage group, for ten
# minutes. The probe must carry its own bound on each node, and a hung node must read
# as not mounted (ERR_CODE 2) within it.
#
# Self-contained: extracts only the function and stubs ceph, cmd (runs the command
# here once per node), mountpoint, mount, umount and systemctl, so it needs no
# cluster.   Run: bash test_health_ceph_mds_check.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fn="$(awk '/^health_ceph_mds_check\(\)/{f=1} f{print} f&&/^}/{exit}' "$DIR/../modules/sdk_health.sh")"
[ -n "$fn" ] || { echo "FAIL: health_ceph_mds_check not extracted"; exit 1; }
eval "$fn"

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ----------------------------------------------------------------
# HUNG lists the nodes whose cephfs mount hangs: mountpoint there blocks until killed.
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p $T/bin
cat > $T/bin/mountpoint <<'EOF'
#!/bin/bash
[[ " $HUNG " == *" $NODE "* ]] && exec sleep 600
echo "$2 is a mountpoint"
EOF
printf '#!/bin/bash\nexit 0\n' > $T/bin/mount ; cp $T/bin/mount $T/bin/umount
printf '#!/bin/bash\necho SubState=running\n' > $T/bin/systemctl
chmod +x $T/bin/*
export PATH=$T/bin:$PATH HUNG=""

CUBE_NODE_CONTROL_HOSTNAMES=(c1 c2 c3)
CUBE_NODE_LIST_HOSTNAMES=(c1 c2 c3 p1)
CEPHFS_STORE_DIR=/mnt/cephfs
SRVSTO=2
CEPH=fake_ceph
fake_ceph() {
    [ "$1" = status ] && echo '{"fsmap":{"up":1,"up:standby":1,"by_rank":[{"name":"c2","status":"up:active"},{"name":"c1","status":"up:standby-replay"}]}}'
}
shared_ip() { echo 10.1.0.100 ; }
_health_fail_log() { : ; }
# cmd -v|-cv "<command>": run it here once per node, as ssh would there
cmd() {
    local nodes=("${CUBE_NODE_LIST_HOSTNAMES[@]}") n
    [ "$1" = -cv ] && nodes=("${CUBE_NODE_CONTROL_HOSTNAMES[@]}")
    for n in "${nodes[@]}" ; do
        printf '%s|0|%s\n' $n "$(NODE=$n bash -c "$2" 2>/dev/null)"
    done
}

# One check under a 60s guard: prints "<ERR_CODE> <seconds>", "hung" if it outlives it.
run() {
    local s=$SECONDS out
    out=$(timeout 60 bash -c "$(declare -f health_ceph_mds_check cmd fake_ceph shared_ip _health_fail_log)
        $(declare -p CUBE_NODE_CONTROL_HOSTNAMES CUBE_NODE_LIST_HOSTNAMES CEPHFS_STORE_DIR SRVSTO CEPH)
        ERR_CODE=0 ERR_MSG= ERR_LOG= ; health_ceph_mds_check ; echo \$ERR_CODE" 2>/dev/null)
    [ $? -eq 124 ] && out=hung
    echo "$out $((SECONDS - s))"
}
fast() { [ "${1#* }" -le 15 ] && echo yes || echo "no (${1#* }s)" ; }

# 1. every node mounted -> ok
r=$(run) ; chk "1 code" "${r% *}" 0

# 2. c1's mount hangs -> not all mounted, within the bound
HUNG="c1" ; r=$(run) ; chk "2 code" "${r% *}" 2 ; chk "2 bounded" "$(fast "$r")" yes

# 3. two nodes hang, a control and a compute -> the same
HUNG="c1 p1" ; r=$(run) ; chk "3 code" "${r% *}" 2 ; chk "3 bounded" "$(fast "$r")" yes

echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: health_ceph_mds_check" ; exit 0 ; } || exit 1
