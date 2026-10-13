#!/bin/bash
#
# Unit test for thanos_objstore_refresh in ../modules/sdk_thanos.sh.
#
# A boot commit no longer writes objstore.yml (it must not wait on RGW before
# /run/cube_commit_done, which the compute nodes and so their OSDs wait for), so
# config_prometheus runs this from node_start instead, after the commit. Thanos reads the
# file only at start: a rewritten file needs the units restarted, and an unchanged one must
# not bounce them on every boot. A file that was missing means the commit held the units
# back -- the sidecar and the store gateway stopped, the compactor masked -- so writing it
# starts them and has pacemaker look at the compactor again.
#
# Self-contained: extracts the three functions and stubs radosgw-admin, s3cmd, chown,
# systemctl, pcs and the log calls, with the config path moved into a temp dir.
#   Run: bash test_thanos_objstore_refresh.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_thanos.sh"
TMP=$(mktemp -d)

for f in _thanos_objstore_conf thanos_objstore_setup thanos_objstore_refresh ; do
    body="$(awk -v f="$f" '$0 ~ "^"f"\\(\\)" {p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $f not extracted"; exit 1; }
    eval "$(printf '%s\n' "$body" | sed -e "s#/etc/thanos#$TMP#g" -e 's#/usr/bin/s3cmd#s3cmd#g')"
done

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ---------------------------------------------------------------
# The rgw user holds AK1/SK1. RGW_DOWN=1 makes every RGW call fail, as when no PG is active.
CONF=$TMP/objstore.yml
EP=10.32.36.10:8888
RESTARTS=$TMP/restarts
RGW_DOWN=0
radosgw-admin() { [ "$RGW_DOWN" = 1 ] && return 1 ; echo '{"keys":[{"access_key":"AK1","secret_key":"SK1"}]}' ; }
s3cmd() { [ "$RGW_DOWN" = 1 ] && return 1 ; return 0 ; }
chown() { : ; }
systemctl() { echo "$*" >> "$RESTARTS" ; }
Quiet() { [ "$1" = -n ] && shift ; "$@" ; return 0 ; }
pcs() { echo "pcs $*" >> "$RESTARTS" ; }
log_info() { : ; }
log_error() { : ; }

want() { printf 'type: S3\nconfig:\n  bucket: %s\n  endpoint: %s\n  access_key: %s\n  secret_key: %s\n  insecure: true\n  signature_version2: false\n' "$@" ; }
restarts() { [ -s "$RESTARTS" ] && paste -s -d';' "$RESTARTS" || echo none ; }
run() { : > "$RESTARTS" ; thanos_objstore_refresh "$@" ; echo $? ; }

# 1. every ordinary boot: the file is current -> no RGW, no restart
RGW_DOWN=1
want thanos $EP AK1 SK1 > "$CONF"
chk "1 rc" "$(run $EP thanos)" 0
chk "1 no restart" "$(restarts)" none

# 2. a file from an older template (the upgrade carried it over) -> rewritten, units restarted
RGW_DOWN=0
want thanos $EP AK1 SK1 | grep -v signature_version2 > "$CONF"
chk "2 rc" "$(run $EP thanos)" 0
chk "2 file" "$(cat "$CONF")" "$(want thanos $EP AK1 SK1)"
chk "2 restart" "$(restarts)" "try-restart thanos-sidecar thanos-store thanos-query"

# 3. a new VIP -> rewritten, units restarted
want thanos 10.32.36.99:8888 AK1 SK1 > "$CONF"
chk "3 rc" "$(run $EP thanos)" 0
chk "3 file" "$(cat "$CONF")" "$(want thanos $EP AK1 SK1)"
chk "3 restart" "$(restarts)" "try-restart thanos-sidecar thanos-store thanos-query"

# 4. no file yet (a control set up before RGW could serve) -> written, the units the commit
#    held back started, the compactor unmasked and handed back to pacemaker
rm -f "$CONF"
chk "4 rc" "$(run $EP thanos)" 0
chk "4 file" "$(cat "$CONF")" "$(want thanos $EP AK1 SK1)"
chk "4 start" "$(restarts)" "start thanos-sidecar thanos-store;unmask thanos-compact;pcs resource refresh thanos-compact"

# 4b. no file yet and RGW still down -> the setup fails, nothing started, the compactor stays masked
RGW_DOWN=1
rm -f "$CONF"
chk "4b rc" "$(run $EP thanos)" 1
chk "4b no file" "$([ -e "$CONF" ] && echo present || echo absent)" absent
chk "4b nothing started" "$(restarts)" none
RGW_DOWN=0

# 5. stale file and RGW down -> the setup fails, the old file stays, nothing restarted
RGW_DOWN=1
want thanos 10.32.36.99:8888 AK1 SK1 > "$CONF"
chk "5 rc" "$(run $EP thanos)" 1
chk "5 file kept" "$(cat "$CONF")" "$(want thanos 10.32.36.99:8888 AK1 SK1)"
chk "5 no restart" "$(restarts)" none

# 6. no endpoint -> usage error from the setup, nothing restarted
RGW_DOWN=0
chk "6 rc" "$(run "" thanos)" 1
chk "6 no restart" "$(restarts)" none

rm -rf "$TMP"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: thanos objstore refresh" ; exit 0 ; } || exit 1
