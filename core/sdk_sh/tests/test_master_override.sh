#!/bin/bash
#
# Unit test for the one-time master override (#2027): cube_master_control in
# ../../main/proj_functions, power_master_override and
# power_master_override_adopt in ../modules/sdk_power.sh.
#
# Self-contained: extracts just these functions and mocks ping/ssh/is_sshable,
# so it needs no cluster.  Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# tunings come from a stub file instead of /etc/settings.txt
TUN=$TMP/tuning
HEX_TUN=$TUN SETTINGS_TXT=
extract(){ awk -v f="^$2\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$1"; }
for fn in cube_master_control ; do
    body="$(extract "$DIR/../../main/proj_functions" $fn | sed "s|/usr/sbin/hex_tuning /etc/settings.txt|\$TUN|")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done
for fn in power_master_override power_master_override_adopt ; do
    body="$(extract "$DIR/../modules/sdk_power.sh" $fn)"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

LOG=$TMP/log
CUBE_MASTER_OVERRIDE=$TMP/override
CUBE_DONE=$TMP/commit_done
HOSTNAME=c2
tun(){ printf 'T_cubesys_control_hosts=%s\nT_cubesys_controller=%s\nT_net_hostname=%s\n' "$1" "${2:-}" "${3:-$HOSTNAME}" > "$TUN" ; }

# --- mocks: UP lists the nodes answering ping+ssh, PINGONLY ping alone;
# PEER_<n> is n's override
UP="c2 c3" PINGONLY=
up(){ echo " $UP " | grep -q " $1 " ; }
ping(){ up "${@: -1}" || echo " $PINGONLY " | grep -q " ${@: -1} " ; }
is_sshable(){ up "$1" ; }
ssh(){
    local n=${1#root@} ; shift
    echo "ssh $n $*" >> "$LOG"
    up "$n" || return 255
    case "$*" in
        "echo "*) eval "PEER_$n=$(echo "$*" | awk '{print $2}')" ;;
        "cat "*) eval "echo \${PEER_$n:-}" ;;
    esac
}
timeout(){ shift ; "$@" ; }
Error(){ echo "Error $*" >> "$LOG" ; exit 1 ; }
log_info(){ : ; } ; log_warning(){ echo "warn $*" >> "$LOG" ; }
saw(){ grep -qe "$1" "$LOG" && echo y || echo n ; }
ovr(){ cat "$CUBE_MASTER_OVERRIDE" 2>/dev/null ; }
reset(){ : > "$LOG" ; rm -f "$CUBE_MASTER_OVERRIDE" "$CUBE_DONE" ; PEER_c1= PEER_c2= PEER_c3= ; }

# 1. cube_master_control
reset ; tun c1,c2,c3
chk "1 first control host"      "$(cube_master_control)" "c1"
echo c3 > "$CUBE_MASTER_OVERRIDE"
chk "1 override"                "$(cube_master_control)" "c3"
echo c9 > "$CUBE_MASTER_OVERRIDE"
chk "1 override not a control"  "$(cube_master_control)" "c1"
rm -f "$CUBE_MASTER_OVERRIDE" ; tun "" ctl
chk "1 non-HA controller"       "$(cube_master_control)" "ctl"
tun "" "" self
chk "1 non-HA self"             "$(cube_master_control)" "self"

# 2. power_master_override refusals: nothing written anywhere
tun c1,c2,c3
refused(){ reset ; [ -n "${2:-}" ] && touch "$CUBE_DONE" ; ( power_master_override $1 ) >/dev/null ; echo "$?:$(ovr):$(saw 'ssh .* echo')" ; }
UP="c2 c3"
chk "2 not a control"    "$(refused c9)"    "1::n"
chk "2 committed"        "$(refused c2 y)"  "1::n"
chk "2 already master"   "$(refused c1)"    "1::n"
UP="c1 c2 c3"
chk "2 master reachable" "$(refused c2)"    "1::n"
UP="c2 c3" PINGONLY=c1
chk "2 master pings"     "$(refused c2)"    "1::n"
PINGONLY=
UP="c2"
chk "2 target unsshable" "$(refused c3)"    "1::n"

# 3. master down: written on the target, here and every reachable control
UP="c2 c3" ; reset
( power_master_override c3 ) >/dev/null ; rc=$?
chk "3 rc"                 "$rc"                     "0"
chk "3 local"              "$(ovr)"                  "c3"
chk "3 target"             "$(saw 'ssh c3 echo c3')" "y"
chk "3 never the master"   "$(saw 'ssh c1 ')"        "n"
reset
( power_master_override c2 ) >/dev/null
chk "3 self local"         "$(ovr)"                  "c2"
chk "3 self peer"          "$(saw 'ssh c3 echo c2')" "y"
# an override already in effect is the master to check
echo c3 > "$CUBE_MASTER_OVERRIDE" ; UP="c1 c2" ; : > "$LOG"
( power_master_override c1 ) >/dev/null ; rc=$?
chk "3 re-override rc"     "$rc"                     "0"
chk "3 re-override local"  "$(ovr)"                  "c1"

# 4. adopt
UP="c1 c3" ; reset ; PEER_c3=c3
power_master_override_adopt
chk "4 adopted from peer"  "$(ovr)"                  "c3"
: > "$LOG" ; power_master_override_adopt
chk "4 local kept, no ssh" "$(saw ssh)"              "n"
reset ; UP="c3" ; PEER_c1=c3
power_master_override_adopt
chk "4 down peer skipped"  "$(ovr)"                  ""
chk "4 down peer no ssh"   "$(saw 'ssh c1')"         "n"
reset ; UP="c1 c3"
power_master_override_adopt ; rc=$?
chk "4 none rc"            "$rc"                     "0"
chk "4 none"               "$(ovr)"                  ""

echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: master override" ; exit 0 ; } || exit 1
