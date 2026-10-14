#!/bin/bash
#
# Unit test for migrate_octavia_amphora_vip_advertise in ../modules/sdk_migrate.sh:
# a one-time migration that installs the VIP re-announce timer on every amphora
# over ssh. Only the master control works; amphorae that already have the timer
# are left alone; it is marked done only when every amphora has the timer (a down
# one is retried, and past the bound left for a later boot); no amphorae = done.
# Fakes the DB, ssh/scp, the clock and the files; needs no cluster.
#   Run: bash test_migrate_octavia_amphora_vip_advertise.sh
#
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); trap 'rm -rf $T' EXIT
sed -n "/^migrate_octavia_amphora_vip_advertise()/,/^}/p" $D/../modules/sdk_migrate.sh |
    sed -e "s|/usr/share/cube/octavia/amphora-vip-advertise|$T/src|" -e "s|/etc/octavia/octavia_ssh_key|$T/key|" > $T/fn.sh
source $T/fn.sh
mkdir -p $T/src $T/state; touch $T/key
FAILS=0
check() { if [ "$2" = "$3" ] ; then echo "ok   $1" ; else echo "FAIL $1: got $2 want $3" ; FAILS=$((FAILS+1)) ; fi ; }
STATE_DIR=$T/state; HOSTNAME=c1
log_info() { :; }; log_warning() { echo warn >> $T/log; }
CONTROL=1; is_control_node() { [ $CONTROL = 1 ]; }
MASTER=c1; HEX_SDK=fake_sdk; fake_sdk() { [ "$1" = cube_master_control ] && echo $MASTER; }
AMPS="10.254.0.1 10.254.0.2 10.254.0.3"; MYSQL=db; db() { [ -n "$AMPS" ] && printf '%s\n' $AMPS; return 0; }
sleep() { SECONDS=$((SECONDS + $1)); ROUND=$((ROUND + 1)); }
timeout() { shift; "$@"; }
# per amphora: $T/st/<ip> = has (timer enabled) | down | <round from which it is up>
target() { for a ; do case $a in ubuntu@*) h=${a#ubuntu@}; echo ${h%%:*} ;; esac ; done | head -1; }
up() { local s=$(cat $T/st/$1 2>/dev/null || echo 0); [ "$s" = has ] && return 0; [ "$s" = down ] && return 1; [ $ROUND -ge $s ]; }
ssh() { local h=$(target "$@"); up $h || return 255
        case "$*" in *is-enabled*) [ "$(cat $T/st/$h 2>/dev/null)" = has ] ;; *) echo $h >> $T/installed; echo has > $T/st/$h ;; esac ; }
scp() { local h=$(target "$@"); up $h || return 1; }
run() { rm -rf $T/st $T/log $T/installed; mkdir -p $T/st; ROUND=0; SECONDS=0; "$@"
        migrate_octavia_amphora_vip_advertise 600
        echo "marker=$([ -f $T/state/octavia_amphora_vip_advertise_migrated ] && echo y || echo n) installed=$(sort $T/installed 2>/dev/null | tr '\n' ' ')warn=$([ -e $T/log ] && echo y || echo n)"
        rm -f $T/state/*; }

check "all amphorae get the timer" "$(run :)" "marker=y installed=10.254.0.1 10.254.0.2 10.254.0.3 warn=n"
check "an amphora with the timer is left alone" "$(run eval 'echo has > $T/st/10.254.0.2')" "marker=y installed=10.254.0.1 10.254.0.3 warn=n"
check "a booting amphora is retried, then done" "$(run eval 'echo 2 > $T/st/10.254.0.3')" "marker=y installed=10.254.0.1 10.254.0.2 10.254.0.3 warn=n"
check "a down amphora: not marked, left for a later boot" "$(run eval 'echo down > $T/st/10.254.0.1')" "marker=n installed=10.254.0.2 10.254.0.3 warn=y"
AMPS=""
check "no amphorae: marked done" "$(run :)" "marker=y installed=warn=n"
AMPS="10.254.0.1"; MASTER=c2
check "not the master: marked, nothing installed" "$(run :)" "marker=y installed=warn=n"
MASTER=c1; touch $T/state/octavia_amphora_vip_advertise_migrated; rm -rf $T/st $T/installed; mkdir -p $T/st
migrate_octavia_amphora_vip_advertise 600
check "already migrated: does nothing" "$(cat $T/installed 2>/dev/null)" ""

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS FAILED"; exit 1; }
