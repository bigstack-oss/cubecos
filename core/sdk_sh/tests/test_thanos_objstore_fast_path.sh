#!/bin/bash
#
# Unit test for thanos_objstore_setup in ../modules/sdk_thanos.sh, the fast path.
#
# On a cold power cycle of a cluster whose OSDs sit on the compute nodes, the controls
# commit prometheus while those OSDs are still down: they start only in the computes'
# own bootstrap, which waits for the controls. Every radosgw-admin call then blocks, so
# the setup spent the caller's whole timeout re-deriving a file the node already had --
# 120s per control on QA 10.32.36.10. A file that is already exactly what the setup
# would write is now left alone without touching RGW; a missing or different one still
# goes through radosgw-admin and s3cmd.
#
# Self-contained: extracts only the two functions and stubs radosgw-admin, s3cmd, chown
# and the log calls, with the config path moved into a temp dir, so it needs no cluster.
#   Run: bash test_thanos_objstore_fast_path.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_thanos.sh"
TMP=$(mktemp -d)

for f in _thanos_objstore_conf thanos_objstore_setup ; do
    body="$(awk -v f="$f" '$0 ~ "^"f"\\(\\)" {p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $f not extracted"; exit 1; }
    eval "$(printf '%s\n' "$body" | sed -e "s#/etc/thanos#$TMP#g" -e 's#/usr/bin/s3cmd#s3cmd#g')"
done

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ---------------------------------------------------------------
# Every RGW-side call is counted in $CALLS; the rgw user holds AK1/SK1.
CALLS=$TMP/calls
CONF=$TMP/objstore.yml
EP=10.32.36.10:8888
radosgw-admin() { echo radosgw-admin >> "$CALLS" ; echo '{"keys":[{"access_key":"AK1","secret_key":"SK1"}]}' ; }
s3cmd() { echo s3cmd >> "$CALLS" ; return 0 ; }
chown() { : ; }
log_info() { : ; }
log_error() { : ; }

want() {    # want <bucket> <endpoint> <ak> <sk>: the file as the setup writes it
    printf 'type: S3\nconfig:\n  bucket: %s\n  endpoint: %s\n  access_key: %s\n  secret_key: %s\n  insecure: true\n  signature_version2: false\n' "$@"
}
calls() { [ -e "$CALLS" ] && wc -l < "$CALLS" | tr -d ' ' || echo 0 ; }
run() { : > "$CALLS" ; thanos_objstore_setup "$@" ; echo $? ; }

# 1. first bootstrap, no file -> RGW, file written
rm -f "$CONF"
chk "1 rc" "$(run $EP thanos)" 0
chk "1 file" "$(cat "$CONF")" "$(want thanos $EP AK1 SK1)"
chk "1 rgw called" "$(calls)" 4

# 2. power cycle, file already current -> no RGW at all, file untouched
want thanos $EP AK1 SK1 > "$CONF" ; chmod 0640 "$CONF"
before=$(stat -c %i:%Y "$CONF")
chk "2 rc" "$(run $EP thanos)" 0
chk "2 no rgw" "$(calls)" 0
chk "2 untouched" "$(stat -c %i:%Y "$CONF")" "$before"

# 3. current file with a drifted mode -> still no RGW, mode re-asserted
chmod 0644 "$CONF"
chk "3 rc" "$(run $EP thanos)" 0
chk "3 no rgw" "$(calls)" 0
chk "3 mode" "$(stat -c %a "$CONF")" 640

# 4. new VIP -> endpoint differs -> RGW, file rewritten
want thanos 10.32.36.99:8888 AK1 SK1 > "$CONF"
chk "4 rc" "$(run $EP thanos)" 0
chk "4 rgw called" "$(calls)" 4
chk "4 file" "$(cat "$CONF")" "$(want thanos $EP AK1 SK1)"

# 5. different bucket -> RGW
want other $EP AK1 SK1 > "$CONF"
run $EP thanos >/dev/null
chk "5 rgw called" "$(calls)" 4

# 6. a file from an older template (no signature_version2 line) -> RGW, rewritten
want thanos $EP AK1 SK1 | grep -v signature_version2 > "$CONF"
run $EP thanos >/dev/null
chk "6 rgw called" "$(calls)" 4
chk "6 file" "$(cat "$CONF")" "$(want thanos $EP AK1 SK1)"

# 7. empty or null keys -> RGW
want thanos $EP "" SK1 > "$CONF"
run $EP thanos >/dev/null
chk "7 empty ak" "$(calls)" 4
want thanos $EP AK1 null > "$CONF"
run $EP thanos >/dev/null
chk "7 null sk" "$(calls)" 4

# 8. no endpoint -> usage error, nothing called
chk "8 rc" "$(run "" thanos)" 1
chk "8 no rgw" "$(calls)" 0

rm -rf "$TMP"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: thanos objstore fast path" ; exit 0 ; } || exit 1
