#!/bin/bash
#
# ceph_mirror_tuning_set / _clear, ceph_mirror_pair / _unpair, ceph_mirror_image_state_sync and
# the normal ceph_mirror_promote_site / _image: site pair records the pairing as ceph.mirror.*
# tunings so a boot rebuilds /etc/ceph/*-site.conf (#439); a normal promote refuses when the
# peer is unknown or unreachable instead of forcing.
#
#   Run: bash test_ceph_mirror_pair_tuning.sh       (needs yq, mikefarah v4)
#   SRC=<other sdk_ceph.sh> bash test_ceph_mirror_pair_tuning.sh   runs it against another copy
#

SRC=${SRC:-$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_ceph.sh}
if ! command -v yq >/dev/null 2>&1 ; then
    echo "SKIP: yq is not installed"
    exit 0
fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-46s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-46s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

for fn in _ceph_mirror_tuning_apply ceph_mirror_tuning_set ceph_mirror_tuning_clear \
    ceph_mirror_image_state_sync ceph_mirror_peer_check ceph_mirror_promote_site ceph_mirror_promote_image \
    ceph_mirror_demote_synced_wait ceph_mirror_image_promote_retry \
    ceph_mirror_pair ceph_mirror_unpair ceph_basic_config_gen ; do
    sed -n "/^$fn()/,/^}/p" "$SRC" > "$T/fn.sh"
    if [ -s "$T/fn.sh" ] ; then
        source "$T/fn.sh"
    else
        chk "$fn exists" missing present
        eval "$fn(){ return 127; }"
    fi
done

POLICY_DIR=$T/policies
mkdir -p "$POLICY_DIR/tuning"
cp "$(dirname "${BASH_SOURCE[0]}")/../../policies/tuning/tuning1_0.yml" "$POLICY_DIR/tuning/"
policy=$POLICY_DIR/tuning/tuning1_0.yml
yq -i '.tunings += [
    {"enabled": true, "name": "unrelated.key", "value": "keep"},
    {"enabled": true, "name": "ceph.mirror.meta.sync", "value": "true"},
    {"enabled": true, "name": "ceph.mirror.rule.1.volume", "value": "id1"}
]' "$policy"
cp "$policy" "$T/base.yml"
# shellcheck disable=SC2034  # read by the sourced functions
HEX_CFG=hex_cfg
hex_cfg(){
    echo "$*" >> "$T/apply.log"
    [ "$APPLY_FAIL" != 1 ] || return 1
    [ "$1" = apply ] || return 1
    cp "$2/tuning/tuning1_0.yml" "$T/applied.yml" || return 1
    cp "$T/applied.yml" "$policy"
}
MakeTempDir(){ mktemp -d "$T/apply.XXXXXX"; }
ours='^ceph\.mirror\.(enabled|name|peer\.[0-9]+\.(name|ipaddr|secret))$'
count_ours(){ yq "[.tunings[] | select(.name | test(\"$ours\"))] | length" "$policy"; }
kept(){ yq -o=json "$policy" | jq -c '[.tunings[] | select(.name == "unrelated.key" or .name == "ceph.mirror.meta.sync" or .name == "ceph.mirror.rule.1.volume")]'; }
keep=$(kept)
: > "$T/apply.log"
ceph_mirror_tuning_set self peer 10.0.0.2
chk "set succeeds" "$?" 0
chk "five pairing tunings" "$(count_ours)" 5
chk "set exact names, values, enabled flags" "$(yq -o=json "$policy" | jq -c '[.tunings[] | select(.name | startswith("ceph.mirror.")) | select(.name != "ceph.mirror.meta.sync" and .name != "ceph.mirror.rule.1.volume")]')" \
    '[{"enabled":true,"name":"ceph.mirror.enabled","value":"true"},{"enabled":true,"name":"ceph.mirror.name","value":"self"},{"enabled":true,"name":"ceph.mirror.peer.1.name","value":"peer"},{"enabled":true,"name":"ceph.mirror.peer.1.ipaddr","value":"10.0.0.2"},{"enabled":true,"name":"ceph.mirror.peer.1.secret","value":""}]'
chk "unrelated, meta and rule tunings preserved" "$(kept)" "$keep"
# config_ceph indexes peer.N.secret alongside peer.N.name, so it must exist, empty
chk "peer secret present and empty" "$(yq -o=json "$policy" | jq -c '[.tunings[] | select(.name | test("secret$")) | .value]')" '[""]'

yq -i '.tunings += [{"name": "ceph.mirror.peer.9.secret", "value": "old"}, {"name": "ceph.mirror.peer.9.name", "value": "old"}]' "$policy"
ceph_mirror_tuning_set self other 10.0.0.3
chk "second set replaces all pairing entries" "$(count_ours)" 5
chk "second peer value" "$(yq '.tunings[] | select(.name == "ceph.mirror.peer.1.name") | .value' "$policy")" other
chk "second set drops the old peer.9 entries" "$(yq '[.tunings[] | select(.name == "ceph.mirror.peer.9.secret" or .name == "ceph.mirror.peer.9.name")] | length' "$policy")" 0
ceph_mirror_tuning_clear
chk "clear succeeds" "$?" 0
chk "clear removes pairing entries" "$(count_ours)" 0
chk "clear leaves only the other tunings" "$(yq -o=json "$policy" | jq -c '[.tunings[].name]')" '["unrelated.key","ceph.mirror.meta.sync","ceph.mirror.rule.1.volume"]'
chk "clear preserves unrelated tunings" "$(kept)" "$keep"
: > "$T/apply.log"
ceph_mirror_tuning_clear
chk "clear absent entries succeeds" "$?" 0
chk "clear absent entries does not apply" "$(cat "$T/apply.log")" ""
for args in 'self peer' 'self "" vip' '"" peer vip'; do
    eval "ceph_mirror_tuning_set $args" 2>/dev/null
    chk "missing argument: $args" "$?" 1
done
chk "invalid set does not apply" "$(cat "$T/apply.log")" ""
APPLY_FAIL=1
ceph_mirror_tuning_set self peer vip
chk "apply failure propagates" "$?" 1
APPLY_FAIL=0
cp "$(dirname "${BASH_SOURCE[0]}")/../../policies/tuning/tuning1_0.yml" "$policy"
: > "$T/apply.log"
ceph_mirror_tuning_clear
chk "absent tunings list clear succeeds" "$?" 0
chk "absent tunings list does not apply" "$(cat "$T/apply.log")" ""
ceph_mirror_tuning_set self peer vip
chk "absent tunings list set succeeds" "$?" 0
chk "absent tunings list gets five entries" "$(count_ours)" 5

# shellcheck disable=SC2034  # read by the sourced functions
BUILTIN_BACKPOOL=cinder-volumes
# shellcheck disable=SC2034  # read by the sourced functions
HEX_SDK=hex_sdk
Quiet(){ [ "$1" != -n ] || shift; "$@" >/dev/null 2>&1; }
rbd(){
    echo "$*" >> "$T/rbd.log"
    case "$*" in
        'mirror pool status '*) echo '{"images":[{"name":"volume-id1"},{"name":"volume-id2"}]}' ;;
        'info '*volume-id1*) echo "{\"mirroring\":{\"primary\":${ID1_PRIMARY:-false}}}" ;;
        'info '*) echo '{"mirroring":{"primary":true}}' ;;
    esac
    return 0
}
: > "$T/rbd.log"
ceph_mirror_image_state_sync ""
chk "empty rules touch no images" "$(cat "$T/rbd.log")" ""
ceph_mirror_image_state_sync 'id1,' >/dev/null
chk "nonempty rules disable only unlisted image" "$(sed -n '/^mirror image disable /p' "$T/rbd.log")" 'mirror image disable cinder-volumes/volume-id2 --force'

ceph_mirror_peer_vip(){ echo "$PEER_VIP"; }
ssh(){
    echo "$*" >> "$T/ssh.log"
    case "$*" in
        *'ceph_mirror_tuning_set '*) return "${REMOTE_SET_FAIL:-0}" ;;
        *'ceph_mirror_tuning_clear') return "${REMOTE_CLEAR_FAIL:-0}" ;;
        *'grep cubesys.controller'*) echo peer ;;
        *'cat /root/.ssh/id_rsa.pub'*) echo public-key ;;
    esac
    return "${SSH_FAIL:-0}"
}
sshpass(){ shift 2; "$@"; }
timeout(){ shift; "$@"; }
sleep(){ :; }
reset_logs(){ : > "$T/rbd.log"; : > "$T/ssh.log"; }
no_promote(){ sed -n '/^mirror image promote /p' "$T/rbd.log"; }
missing_error='Error: no paired site found (/etc/ceph/*-site.conf missing), not promoting. Pair the sites again, or use a force promote if the peer site is down'
remote_error='Error: remote site 10.0.0.2 unreachable, not promoting: a normal promote has to demote it first. Use a force promote if that site is down'
for fn in ceph_mirror_promote_site ceph_mirror_promote_image ; do
    args=normal
    [ "$fn" != ceph_mirror_promote_image ] || args='id1 normal'
    PEER_VIP='' SSH_FAIL=0
    reset_logs
    $fn $args > "$T/out" 2> "$T/err"
    chk "$fn missing peer returns 1" "$?" 1
    chk "$fn missing peer error" "$(cat "$T/err")" "$missing_error"
    chk "$fn missing peer no promote" "$(no_promote)" ""
    chk "$fn missing peer no ssh" "$(cat "$T/ssh.log")" ""
    PEER_VIP=10.0.0.2 SSH_FAIL=1
    reset_logs
    $fn $args > "$T/out" 2> "$T/err"
    chk "$fn unreachable returns 1" "$?" 1
    chk "$fn unreachable error" "$(cat "$T/err")" "$remote_error"
    chk "$fn unreachable no promote" "$(no_promote)" ""
    chk "$fn unreachable no force or demote" "$(cat "$T/rbd.log" "$T/ssh.log" | sed -n '/--force\|ceph_mirror_demote/p')" ""
done
PEER_VIP=10.0.0.2 SSH_FAIL=0
reset_logs
ceph_mirror_promote_site normal >/dev/null
chk "normal site promote succeeds" "$?" 0
chk "normal site demotes peer" "$(sed -n '/ceph_mirror_demote_site/p' "$T/ssh.log")" '-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@10.0.0.2 hex_sdk ceph_mirror_demote_site normal'
chk "normal promotes only non-primary without force" "$(no_promote)" 'mirror image promote cinder-volumes/volume-id1'
PEER_VIP='' SSH_FAIL=1
reset_logs
ceph_mirror_promote_site force >/dev/null
chk "force with no peer still promotes" "$(no_promote)" 'mirror image promote --force cinder-volumes/volume-id1'

SSH_FAIL=0
reset_logs
ceph_basic_config_gen "$T/ceph.conf" 10.0.0.2
chk "key config generation bounds ssh connect" "$(sed -n '/ConnectTimeout=10/p' "$T/ssh.log" | wc -l | xargs)" 1

cmd(){ :; }
cubectl(){ :; }
shared_ip(){ echo 10.0.0.1; }
hostname(){ echo self-host; }
ceph_mirror_daemon_restart(){ :; }
ceph_mirror_pool_peer_set(){ :; }
ceph_basic_config_gen(){ :; }
Error(){ echo "Unexpected Error: $*" >&2; return 1; }
# Pair only reads this key; no real host files or commands are used.
cat(){
    if [ "$1" = /root/.ssh/id_rsa.pub ] ; then
        echo public-key
    else
        command cat "$@"
    fi
}
SETTINGS_TXT=$T/settings.txt
echo cubesys.controller=self > "$SETTINGS_TXT"
ceph_mirror_tuning_set(){ echo "$*" >> "$T/set.log"; return "${LOCAL_SET_FAIL:-0}"; }
for REMOTE_SET_FAIL in 0 1 ; do
    reset_logs
    : > "$T/set.log"
    ceph_mirror_pair 10.0.0.2 password > "$T/out" 2> "$T/err"
    chk "pair remote failure=$REMOTE_SET_FAIL status" "$?" "$REMOTE_SET_FAIL"
    chk "pair local tuning arguments" "$(cat "$T/set.log")" 'self-10.0.0.1 peer-10.0.0.2 10.0.0.2'
    chk "pair remote tuning arguments" "$(sed -n '/ceph_mirror_tuning_set/p' "$T/ssh.log")" '-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@10.0.0.2 hex_sdk ceph_mirror_tuning_set peer-10.0.0.2 self-10.0.0.1 10.0.0.1'
done
chk "pair remote failure error" "$(cat "$T/err")" 'Error: failed to record the pairing on root@10.0.0.2; it will not survive a reboot'
LOCAL_SET_FAIL=1 REMOTE_SET_FAIL=0
reset_logs
ceph_mirror_pair 10.0.0.2 password > "$T/out" 2> "$T/err"
chk "pair local failure status" "$?" 1
chk "pair local failure still attempts peer" "$(sed -n '/ceph_mirror_tuning_set/p' "$T/ssh.log" | wc -l | xargs)" 1
chk "pair local failure error" "$(cat "$T/err")" 'Error: failed to record the pairing on local site; it will not survive a reboot'

find(){ :; }
ID1_PRIMARY=true # unpair runs where every mirrored image is primary
ceph_mirror_disable(){ echo disable >> "$T/unpair.log"; }
ceph_mirror_tuning_clear(){ echo clear >> "$T/unpair.log"; return "${CLEAR_FAIL:-0}"; }
PEER_VIP=
: > "$T/unpair.log"
(ceph_mirror_unpair) > "$T/out" 2> "$T/err"
chk "unpaired exits successfully" "$?" 0
chk "unpaired still clears local after disable" "$(paste -sd'|' "$T/unpair.log")" 'disable|clear'
chk "unpaired early exit message" "$(cat "$T/out")" 'already unpaired'
CLEAR_FAIL=1
(ceph_mirror_unpair) > "$T/out" 2> "$T/err"
chk "clear failure does not block unpair" "$?" 0
chk "unpair clear failure error" "$(cat "$T/err")" 'Error: failed to clear the pairing tunings on local site'
CLEAR_FAIL=0 PEER_VIP=10.0.0.2 SSH_FAIL=0
reset_logs
: > "$T/unpair.log"
ceph_mirror_unpair > "$T/out" 2> "$T/err"
chk "paired: local clear after both disables" "$(paste -sd'|' "$T/unpair.log")" 'disable|disable|clear'
chk "paired: peer disabled before its clear" "$(grep -oE 'hex_sdk (ceph_mirror_disable|ceph_mirror_tuning_clear)$' "$T/ssh.log" | cut -d' ' -f2 | paste -sd'|' -)" 'ceph_mirror_disable|ceph_mirror_disable|ceph_mirror_tuning_clear'
chk "paired: no error" "$(cat "$T/err")" ""
REMOTE_CLEAR_FAIL=1
ceph_mirror_unpair > "$T/out" 2> "$T/err"
chk "paired: peer clear failure is reported" "$(cat "$T/err")" 'Error: failed to clear the pairing tunings on root@10.0.0.2'
REMOTE_CLEAR_FAIL=0 CLEAR_FAIL=1
ceph_mirror_unpair > "$T/out" 2> "$T/err"
chk "paired: local clear failure is reported" "$(cat "$T/err")" 'Error: failed to clear the pairing tunings on local site'

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
