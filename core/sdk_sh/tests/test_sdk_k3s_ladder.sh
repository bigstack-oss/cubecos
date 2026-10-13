#!/bin/bash
#
# Unit test for the k3s minor-by-minor upgrade in ../modules/sdk_k3s.sh: k3s_upgrade_ladder
# steps every server up one minor at a time, one server at a time, stops at the first one that
# does not settle, and commits k3s once all run the image's release; k3s_step swaps one node's
# binary. Also checks power_roll_advance (../modules/sdk_power.sh) calls it at the end of a
# roll, before the job is marked done.
#
# Self-contained: extracts just these functions and mocks k3s, etcdctl, hostname, hex_tuning,
# remote_run, systemctl and cubectl, so it needs no cluster. A node's k3s version lives in
# $T/ver/<node>; the image's k3s binaries are scripts that print their version.
# Run: bash test_sdk_k3s_ladder.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_k3s.sh"
POWER="$DIR/../modules/sdk_power.sh"
T=$(mktemp -d)
trap 'rm -rf $T' EXIT

for fn in _k3s_minor _k3s_bin_version _k3s_next_release _k3s_wait_settled k3s_step k3s_upgrade_ladder ; do
    body="$(awk -v f="^${fn}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done

K3S_BIN=$T/usr/local/bin/k3s
K3S_FINAL_BIN=$T/opt/k3s/k3s
K3S_LADDER_DIR=$T/opt/k3s/ladder
K3S_VERSION_FILE=$T/cube-k3s-version
K3S_STEP_TIMEOUT=3
K3S_STEP_POLL=1
HEX_SDK=hex_sdk
SETTINGS_TXT=$T/settings.txt
FINAL=v1.32.13+k3s1
LADDER="v1.27.16+k3s1 v1.28.15+k3s1 v1.29.15+k3s1 v1.30.14+k3s2 v1.31.14+k3s1"

LOG=$T/log
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
saw(){ grep -qe "$1" "$LOG" && echo y || echo n; }
count(){ grep -ce "$1" "$LOG" ; }

# --- the image: a fake k3s binary per release
fakebin(){ mkdir -p "$(dirname $1)" ; printf '#!/bin/sh\necho "k3s version %s (0000000)"\n' "$2" > $1 ; chmod +x $1 ; }
fakebin $K3S_FINAL_BIN $FINAL
for v in $LADDER ; do fakebin $K3S_LADDER_DIR/$v/k3s $v ; done

# --- mocks
log_info(){ echo "info $*" >> "$LOG" ; }
log_error(){ echo "error $*" >> "$LOG" ; }
mkdir -p $T/bin && cat > $T/bin/hex_tuning <<'EOS'
v=$(awk -F' = ' -v k="$2" '$1==k{print $2}' "$1")
eval "T_$(echo $2 | tr . _)=\"\$v\""
EOS
PATH=$T/bin:$PATH
SELF=cc1
NODES=""
STUCK=""        # nodes that never report Ready after a step
FAILSTEP=""     # nodes whose remote k3s_step returns non-zero
is_control_node(){ return 0 ; }
hostname(){ echo $SELF ; }
sleep(){ : ; }
etcdctl(){ return 0 ; }
ip(){ echo "2: eth0    inet $MYIP/24 brd 10.0.0.255 scope global eth0" ; }
cubectl(){ echo "cubectl $*" >> "$LOG" ; }
timeout(){ shift ; "$@" ; }
systemctl(){ echo "systemctl $*" >> "$LOG" ; setver $SELF "$(_k3s_bin_version $K3S_BIN)" ; }
k3s(){
    case "$*" in
        "kubectl get nodes -l node-role.kubernetes.io/control-plane -o json")
            for n in $NODES ; do printf '%s %s\n' $n "$(cat $T/ver/$n)" ; done |
                jq -Rn '{items: [inputs | split(" ") | {metadata: {name: .[0]}, status: {nodeInfo: {kubeletVersion: .[1]}}}]}' ;;
        "kubectl get node "*)
            local n=$4 ready=True
            case " $STUCK " in *" $n "*) ready=False ;; esac
            echo "$(cat $T/ver/$n) $ready" ;;
        "kubectl get --raw=/readyz") return 0 ;;
        *) echo "unexpected k3s $*" >> "$LOG" ; return 1 ;;
    esac
}
remote_run(){
    echo "remote $1 $2" >> "$LOG"
    case "$2" in
        *" k3s_step "*)
            case " $FAILSTEP " in *" $1 "*) return 1 ;; esac
            setver $1 "${2##* }" ;;
    esac
    return 0
}

# Per-node version, and the widest minor spread seen across the servers at any point
setver(){
    echo "$2" > $T/ver/$1
    local spread=$(for n in $NODES ; do _k3s_minor "$(cat $T/ver/$n)" ; done | sort -n | awk 'NR==1{lo=$1} {hi=$1} END{print hi-lo}')
    [ "$spread" -le "$(cat $T/spread)" ] || echo $spread > $T/spread
}
cluster(){   # <ha> <self-is-vip> <node>=<version>...
    : > "$LOG" ; rm -rf $T/ver ; mkdir -p $T/ver ; echo 0 > $T/spread ; rm -f $K3S_VERSION_FILE
    printf 'cubesys.ha = %s\ncubesys.control.vip = 10.0.0.100\n' "$1" > $SETTINGS_TXT
    [ "$2" = y ] && MYIP=10.0.0.100 || MYIP=10.0.0.1
    shift 2
    NODES="" STUCK="" FAILSTEP=""
    local nv
    for nv in "$@" ; do NODES="$NODES ${nv%%=*}" ; echo "${nv#*=}" > $T/ver/${nv%%=*} ; done
    fakebin $K3S_BIN "$(cat $T/ver/$SELF)"
    setver $SELF "$(cat $T/ver/$SELF)"
}
vers(){ for n in $NODES ; do printf '%s ' "$(cat $T/ver/$n)" ; done | sed 's/ $//' ; }

# 1. every server already runs the image's release: nothing to do
cluster true y cc1=$FINAL cc2=$FINAL cc3=$FINAL
k3s_upgrade_ladder ; rc=$?
chk "1 rc"                         "$rc" "0"
chk "1 no step"                    "$(saw 'remote\|systemctl')" "n"
chk "1 no commit"                  "$(saw 'cubectl')" "n"

# 2. HA, versions mixed one minor apart: one server at a time, never more than one minor apart
cluster true y cc1=v1.28.15+k3s1 cc2=v1.27.16+k3s1 cc3=v1.27.16+k3s1
k3s_upgrade_ladder ; rc=$?
chk "2 rc"                         "$rc" "0"
chk "2 all final"                  "$(vers)" "$FINAL $FINAL $FINAL"
chk "2 spread <= 1 minor"          "$(cat $T/spread)" "1"
chk "2 first step cc2 to 1.28"     "$(grep -m1 -e '^remote\|^systemctl' $LOG)" "remote cc2 hex_sdk k3s_step v1.28.15+k3s1"
chk "2 steps: 2 + 3 x 4"           "$(count '^remote .* k3s_step\|^systemctl restart')" "14"
chk "2 self stepped locally"       "$(saw '^remote cc1')" "n"
chk "2 commits k3s last"           "$(tail -1 $LOG)" "cubectl config commit k3s"
chk "2 self records final"         "$(cat $K3S_VERSION_FILE)" "$FINAL"

# 3a. a server that does not settle stops the ladder: later servers untouched, no commit
cluster true y cc1=v1.27.16+k3s1 cc2=v1.27.16+k3s1 cc3=v1.27.16+k3s1
STUCK=cc2
k3s_upgrade_ladder ; rc=$?
chk "3a rc"                        "$([ $rc -ne 0 ] && echo nonzero)" "nonzero"
chk "3a cc3 untouched"             "$(saw '^remote cc3')" "n"
chk "3a no commit"                 "$(saw 'cubectl')" "n"
chk "3a says which"                "$(saw 'error k3s_upgrade_ladder: cc2 not settled on v1.28.15+k3s1')" "y"
chk "3a spread <= 1 minor"         "$(cat $T/spread)" "1"

# 3b. a server whose k3s_step fails stops it the same way
cluster true y cc1=v1.27.16+k3s1 cc2=v1.27.16+k3s1 cc3=v1.27.16+k3s1
FAILSTEP=cc2
k3s_upgrade_ladder ; rc=$?
chk "3b rc"                        "$([ $rc -ne 0 ] && echo nonzero)" "nonzero"
chk "3b cc3 untouched"             "$(saw '^remote cc3')" "n"
chk "3b no commit"                 "$(saw 'cubectl')" "n"
chk "3b says which"                "$(saw 'error k3s_upgrade_ladder: k3s_step v1.28.15+k3s1 failed on cc2')" "y"

# 4. single node: climbs to the end on its own, then commits k3s -- unless told not to
cluster false n cc1=v1.27.16+k3s1
k3s_upgrade_ladder ; rc=$?
chk "4 rc"                         "$rc" "0"
chk "4 final"                      "$(vers)" "$FINAL"
chk "4 one restart per minor"      "$(count '^systemctl restart k3s')" "5"
chk "4 no remote"                  "$(saw '^remote')" "n"
chk "4 commits k3s last"           "$(tail -1 $LOG)" "cubectl config commit k3s"
cluster false n cc1=v1.27.16+k3s1
k3s_upgrade_ladder nocommit ; rc=$?
chk "4 nocommit rc"                "$rc" "0"
chk "4 nocommit final"             "$(vers)" "$FINAL"
chk "4 nocommit no commit"         "$(saw 'cubectl')" "n"

# 5. k3s_step to the version it already runs: no restart, record written
cluster false n cc1=v1.30.14+k3s2
k3s_step v1.30.14+k3s2 ; rc=$?
chk "5 rc"                         "$rc" "0"
chk "5 no restart"                 "$(saw 'systemctl')" "n"
chk "5 recorded"                   "$(cat $K3S_VERSION_FILE)" "v1.30.14+k3s2"

# 6. k3s_step to a release the image does not ship
cluster false n cc1=v1.30.14+k3s2
k3s_step v1.29.1+k3s1 ; rc=$?
chk "6 rc"                         "$rc" "1"
chk "6 no restart"                 "$(saw 'systemctl')" "n"
chk "6 not recorded"               "$([ -e $K3S_VERSION_FILE ] && echo y || echo n)" "n"

# 7. HA, not the VIP holder: hands the whole run to it
cluster true n cc1=v1.27.16+k3s1 cc2=v1.27.16+k3s1
k3s_upgrade_ladder ; rc=$?
chk "7 rc"                         "$rc" "0"
chk "7 forwarded"                  "$(cat $LOG)" "remote 10.0.0.100 hex_sdk k3s_upgrade_ladder "

# 8. the image misses a minor on the way: refuses rather than skip one
mv $K3S_LADDER_DIR/v1.29.15+k3s1 $T/held
cluster false n cc1=v1.28.15+k3s1
k3s_upgrade_ladder ; rc=$?
mv $T/held $K3S_LADDER_DIR/v1.29.15+k3s1
chk "8 rc"                         "$rc" "1"
chk "8 not stepped"                "$(vers)" "v1.28.15+k3s1"
chk "8 says why"                   "$(saw 'ships no v1.29 to step up from v1.28')" "y"

# 9. power_roll_advance runs it at the end of a roll, after the other end-of-roll steps and
#    before the job is marked done
pra="$(awk '/^power_roll_advance\(\)/{p=1} p{print} p&&/^}/{exit}' "$POWER")"
at(){ grep -nF -m1 -e "$1" <<< "$pra" | cut -d: -f1 ; }
call='remote_run $master "$HEX_SDK k3s_upgrade_ladder"'
ladder=$(at "$call") ; done_=$(at '_power_roll_set_str state done')
chk "9 hook present"               "$([ -n "$ladder" ] && echo y || echo n)" "y"
chk "9 after rabbitmq_ticktime"    "$([ "${ladder:-0}" -gt "$(at 'rabbitmq_ticktime')" ] && echo y || echo n)" "y"
chk "9 before state done"          "$([ "${ladder:-999999}" -lt "$done_" ] && echo y || echo n)" "y"
chk "9 on the VIP holder"          "$(grep -cF "$call" <<< "$pra")" "1"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
