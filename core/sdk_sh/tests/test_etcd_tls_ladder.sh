#!/bin/bash
#
# Unit test for etcd_tls_ladder (../modules/sdk_etcd.sh), which moves cube's etcd from TLS
# compat to enforce: PKI to every node, every member serving https, clients over to https,
# then one member at a time into enforce, stopping at the first step that fails. Also checks
# power_roll_advance (../modules/sdk_power.sh) calls it at the end of a roll, before the job
# is marked done.
#
# Self-contained: extracts the functions and mocks cubectl, remote_run, etcdctl, ip,
# hex_tuning, mgmt_ip, systemctl and sleep. A node's state lives under $T: mode/<ip> is what
# `cubectl this-node etcd-refresh` last left its member in, marker/<ip> its compat marker.
# Run: bash test_etcd_tls_ladder.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_etcd.sh"
POWER="$DIR/../modules/sdk_power.sh"
T=$(mktemp -d)
trap 'rm -rf $T' EXIT

for fn in _etcd_tls_ctl _etcd_tls_settled _etcd_tls_on etcd_tls_ladder ; do
    body="$(awk -v f="^${fn}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done

ETCD_PKI_DIR=$T/pki
SETTINGS_TXT=$T/settings.txt
ETCD_TLS_SETTLE_TIMEOUT=4
ETCD_TLS_POLL=1
HEX_SDK=hex_sdk
LOG=$T/log
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
saw(){ grep -qe "$1" "$LOG" && echo y || echo n; }
count(){ grep -ce "$1" "$LOG" ; }
modes(){ local n out="" ; for n in $CONTROLS ; do out+="${out:+ }$(cat $T/mode/$n)" ; done ; echo "$out" ; }
markers(){ ls $T/marker 2>/dev/null | wc -l | tr -d ' ' ; }

# --- mocks
log_info(){ echo "info $*" >> "$LOG" ; }
log_error(){ echo "error $*" >> "$LOG" ; }
mkdir -p $T/bin && cat > $T/bin/hex_tuning <<'EOS'
v=$(awk -F' = ' -v k="$2" '$1==k{print $2}' "$1")
eval "T_$(echo $2 | tr . _)=\"\$v\""
EOS
PATH=$T/bin:$PATH
MYIP=10.0.0.11
CONTROLS="" NODES=""
FAILENFORCE=""   # controls whose etcd-refresh fails once the marker is gone
UNHEALTHY=""     # members that never answer https
FAILRSYNC="" FAILEXEC=""
is_control_node(){ return 0 ; }
mgmt_ip(){ echo -n $MYIP ; }
sleep(){ : ; }
ip(){ echo "2: eth0    inet $MYIP/24 brd 10.0.0.255 scope global eth0" ; }
systemctl(){ echo "systemctl $*" >> "$LOG" ; }
_etcd_tls_ctl(){
    local ep
    for ep in $(echo "$*" | sed -n 's/.*--endpoints=\([^ ]*\).*/\1/p' | tr ',' ' ') ; do
        ep=${ep#https://} ; ep=${ep%:12379}
        case " $UNHEALTHY " in *" $ep "*) ;; *) echo "https://$ep:12379 is healthy, successfully committed proposal" ;; esac
    done
}
refresh(){ # what `cubectl this-node etcd-refresh` does to the member at $1
    if [ -e $T/marker/$1 ] ; then
        echo "refresh $1 compat" >> "$LOG" ; echo compat > $T/mode/$1
    else
        case " $FAILENFORCE " in *" $1 "*) echo "refresh $1 FAILED" >> "$LOG" ; return 1 ;; esac
        echo "refresh $1 enforce" >> "$LOG" ; echo enforce > $T/mode/$1
    fi
}
remote_run(){ local h=$1 ; shift ; echo "remote $h $*" >> "$LOG"
    case "$*" in "cubectl this-node etcd-refresh") refresh $h ;; *) return 1 ;; esac ; }
cubectl(){
    case "$1 $2" in
        "this-node etcd-refresh") refresh $MYIP ;;
        "node rsync") echo "rsync $3" >> "$LOG" ; [ -z "$FAILRSYNC" ] ;;
        "node exec")
            echo "exec $3" >> "$LOG"
            local n
            for n in $NODES ; do
                [ "$n" != "$FAILEXEC" ] || return 1
                [ ! -e $T/marker/$n ] || { rm -f $T/marker/$n ; echo "watch-restart $n" >> "$LOG" ; }
            done ;;
        *) echo "unexpected cubectl $*" >> "$LOG" ; return 1 ;;
    esac
}

# cluster <ha> <controls> [computes]: every node in compat with the PKI, nothing run yet
cluster(){
    rm -rf $T/mode $T/marker $LOG $ETCD_PKI_DIR ; mkdir -p $T/mode $T/marker $ETCD_PKI_DIR ; : > $LOG
    touch $ETCD_PKI_DIR/ca.crt
    CONTROLS=$2 NODES="$2 ${3:-}"
    printf 'cubesys.ha = %s\ncubesys.control.addrs = %s\n' $1 "$(echo $2 | tr ' ' ',')" > $SETTINGS_TXT
    local n ; for n in $NODES ; do touch $T/marker/$n ; done
    for n in $CONTROLS ; do echo compat > $T/mode/$n ; done
    ETCD_TLS_COMPAT_MARK=$T/marker/$MYIP
    FAILENFORCE="" UNHEALTHY="" FAILRSYNC="" FAILEXEC=""
}
HA3="10.0.0.11 10.0.0.12 10.0.0.13"

# 1. HA: the whole ladder, in order
cluster true "$HA3" 10.0.0.21
etcd_tls_ladder ; rc=$?
chk "1 rc"                    "$rc" "0"
chk "1 enforce everywhere"    "$(modes)" "enforce enforce enforce"
chk "1 markers gone"          "$(markers)" "0"
chk "1 etcd-watch restarted"  "$(count '^watch-restart')" "4"
chk "1 order"                 "$(grep -oE '^(rsync|refresh [0-9.]+ [a-z]+|exec)' $LOG | tr '\n' '|')" \
    "rsync|refresh 10.0.0.11 compat|refresh 10.0.0.12 compat|refresh 10.0.0.13 compat|exec|refresh 10.0.0.11 enforce|refresh 10.0.0.12 enforce|refresh 10.0.0.13 enforce|"
chk "1 pushes the PKI dir"    "$(saw "^rsync $ETCD_PKI_DIR$")" "y"
chk "1 self runs locally"     "$(saw 'remote 10.0.0.11')" "n"
chk "1 others over ssh"       "$(count 'remote 10.0.0.1[23] cubectl this-node etcd-refresh')" "4"
chk "1 flip guarded"          "$(grep -c '^exec \[ ! -e .* \] || { rm -f .* && systemctl restart etcd-watch ; }$' $LOG)" "1"
chk "1 says done"             "$(saw 'every member enforces etcd TLS')" "y"

# 2. HA: the second member does not come back enforcing: stop, leave the third alone
cluster true "$HA3"
FAILENFORCE=10.0.0.12
etcd_tls_ladder ; rc=$?
chk "2 rc"                    "$rc" "1"
chk "2 stopped at the second" "$(modes)" "enforce compat compat"
chk "2 third not touched"     "$(saw 'refresh 10.0.0.13 enforce')" "n"
chk "2 says which"            "$(saw 'error etcd_tls_ladder: etcd on 10.0.0.12 did not come back enforcing TLS')" "y"

# 3. HA: a member does not answer https: clients stay on http, no member enforces
cluster true "$HA3"
UNHEALTHY=10.0.0.13
etcd_tls_ladder ; rc=$?
chk "3 rc"                    "$rc" "1"
chk "3 clients not flipped"   "$(markers)" "3"
chk "3 no exec"               "$(saw '^exec')" "n"
chk "3 nobody enforces"       "$(modes)" "compat compat compat"

# 4. HA: run again once done: nothing restarts
cluster true "$HA3" 10.0.0.21
etcd_tls_ladder >/dev/null ; : > $LOG
etcd_tls_ladder ; rc=$?
chk "4 rc"                    "$rc" "0"
chk "4 no etcd-watch restart" "$(saw '^watch-restart')" "n"
chk "4 still enforce"         "$(modes)" "enforce enforce enforce"

# 5. HA: rerun after case 2's failure carries on from there
cluster true "$HA3"
FAILENFORCE=10.0.0.12
etcd_tls_ladder >/dev/null
FAILENFORCE=""
etcd_tls_ladder ; rc=$?
chk "5 rc"                    "$rc" "0"
chk "5 finished"              "$(modes)" "enforce enforce enforce"

# 6. the PKI cannot be pushed: nothing else happens
cluster true "$HA3"
FAILRSYNC=y
etcd_tls_ladder ; rc=$?
chk "6 rc"                    "$rc" "1"
chk "6 no refresh"            "$(saw '^refresh')" "n"

# 7. a node cannot drop its marker: no member enforces
cluster true "$HA3" 10.0.0.21
FAILEXEC=10.0.0.21
etcd_tls_ladder ; rc=$?
chk "7 rc"                    "$rc" "1"
chk "7 nobody enforces"       "$(modes)" "compat compat compat"

# 8. no PKI: nothing to do
cluster true "$HA3"
rm -rf $ETCD_PKI_DIR
etcd_tls_ladder ; rc=$?
chk "8 rc"                    "$rc" "0"
chk "8 nothing run"           "$(grep -cvE '^info' $LOG)" "0"

# 9. single node: local only, no push, no node exec
cluster false "$MYIP"
etcd_tls_ladder ; rc=$?
chk "9 rc"                    "$rc" "0"
chk "9 enforce"               "$(modes)" "enforce"
chk "9 order"                 "$(grep -oE '^(rsync|exec|refresh [0-9.]+ [a-z]+|systemctl .*)' $LOG | tr '\n' '|')" \
    "refresh 10.0.0.11 compat|systemctl restart etcd-watch|refresh 10.0.0.11 enforce|"
chk "9 marker gone"           "$([ -e $ETCD_TLS_COMPAT_MARK ] && echo y || echo n)" "n"
: > $LOG
etcd_tls_ladder ; rc=$?
chk "9 rerun rc"              "$rc" "0"
chk "9 rerun no restart"      "$(saw 'systemctl')" "n"

# 10. power_roll_advance runs it at the end of a roll, after k3s_upgrade_ladder and before
#     the job is marked done
pra="$(awk '/^power_roll_advance\(\)/{p=1} p{print} p&&/^}/{exit}' "$POWER")"
at(){ grep -nF -m1 -e "$1" <<< "$pra" | cut -d: -f1 ; }
call='remote_run $master "$HEX_SDK etcd_tls_ladder"'
ladder=$(at "$call") ; done_=$(at '_power_roll_set_str state done')
chk "10 hook present"         "$([ -n "$ladder" ] && echo y || echo n)" "y"
chk "10 after k3s ladder"     "$([ "${ladder:-0}" -gt "$(at 'k3s_upgrade_ladder')" ] && echo y || echo n)" "y"
chk "10 before state done"    "$([ "${ladder:-999999}" -lt "$done_" ] && echo y || echo n)" "y"
chk "10 once, on the master"  "$(grep -cF "$call" <<< "$pra")" "1"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
