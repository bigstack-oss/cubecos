#!/bin/bash
#
# Flow test for the master override in ../../main/bootstrap_cube_config (#2027).
# A waiting control re-reads the override each pass: named itself -> it runs
# the master bring-up; named a peer -> it waits on that peer's commit. With no
# override the boot is unchanged. A compute waits on the effective master's
# commit plus every other control committed or down.
#
# Runs a copy of the script with its paths moved into a temp dir and stub
# hex_sdk/hex_config/... on PATH; sleep is stubbed to drive the wait loop.
# Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../../main/bootstrap_cube_config"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN=$TMP/bin ; mkdir -p "$BIN"

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

sed -e "s|/usr/sbin/hex_tuning /etc/settings.txt|$TMP/tuning|" \
    -e "s|/etc/appliance/state/configured|$TMP/configured|" \
    -e "s|/etc/appliance/state/boot_mode|$TMP/boot_mode|" \
    -e "s|/run/cube_commit_done|$TMP/commit_done|" \
    -e "s|/run/cube_bootstrap.log|$TMP/bootstrap.log|" \
    -e "s|/store/rolling_recover|$TMP/rolling_recover|" \
    "$SRC" > "$TMP/bootstrap"

# hex_sdk: committed_<host> marks a committed peer, dead_<host> an unsshable
# one, override holds the override
cat > "$BIN/hex_sdk" <<'EOF'
#!/bin/bash
[ "$1" = "-v" ] && shift
echo "hex_sdk $*" >> $TMP/calls
case "$1" in
    remote_run) [ "$3" = stat ] && [ -e $TMP/committed_$2 ] ;;
    cube_controls_committed_or_down) for n in c1 c2 c3 ; do [ "$n" = "$2" ] || [ -e $TMP/dead_$n ] || [ -e $TMP/committed_$n ] || exit 1 ; done ;;
    cube_master_control) o=$(cat $TMP/override 2>/dev/null) ; echo ${o:-c1} ;;
    power_master_override_adopt) [ -s $TMP/override ] || { [ -s $TMP/peer_override ] && cp $TMP/peer_override $TMP/override ; } ; exit 0 ;;
    *) exit 0 ;;
esac
EOF
# hex_config commit drops the commit marker
cat > "$BIN/hex_config" <<'EOF'
#!/bin/bash
echo "hex_config $*" >> $TMP/calls
touch $TMP/commit_done
EOF
# sleep: count passes; at pass $SWITCH_AT the operator sets the override
cat > "$BIN/sleep" <<'EOF'
#!/bin/bash
n=$(( $(cat $TMP/sleeps 2>/dev/null || echo 0) + 1 )) ; echo $n > $TMP/sleeps
[ "$n" = "${SWITCH_AT:-0}" ] && echo $SWITCH_TO > $TMP/override
[ "$n" = "${COMMIT_AT:-0}" ] && touch $TMP/committed_$COMMIT_HOST
[ "$n" -lt 30 ] || kill -9 $PPID
exit 0
EOF
printf '#!/bin/bash\necho $NODE\n' > "$BIN/hostname"
for s in hex_log_event hex_cli journalctl rsync stty ; do printf '#!/bin/bash\nexit 0\n' > "$BIN/$s" ; done
chmod +x "$BIN"/*
export TMP PATH="$BIN:$PATH"

# boot <node> [role]: run the script, wait for its backgrounded bring-up
boot(){
    rm -f $TMP/calls $TMP/sleeps $TMP/commit_done $TMP/boot_mode
    touch $TMP/calls $TMP/configured
    printf 'T_cubesys_control_hosts=c1,c2,c3\nT_net_hostname=%s\nT_cubesys_role=%s\n' "$1" "${2:-control-converged}" > $TMP/tuning
    NODE=$1 bash $TMP/bootstrap >/dev/null 2>&1
    local i ; for i in $(seq 1 100) ; do [ -s $TMP/boot_mode ] && grep -q '^[0-9]' $TMP/boot_mode || break ; /bin/sleep 0.1 ; done
}
saw(){ grep -qe "$1" $TMP/calls && echo y || echo n ; }
master_ran(){ saw 'hex_sdk health_late_start_sweep' ; }
waited_on(){ grep '^hex_sdk remote_run' $TMP/calls | awk '{print $3}' | sort -u | tr '\n' ' ' ; }

# 1. no override: a peer waits on c1, then the peer bring-up
rm -f $TMP/override $TMP/peer_override $TMP/committed_*
COMMIT_AT=2 COMMIT_HOST=c1 SWITCH_AT=0 SWITCH_TO= ; export COMMIT_AT COMMIT_HOST SWITCH_AT SWITCH_TO
boot c2
chk "1 adopt at start"      "$(saw 'hex_sdk power_master_override_adopt')" "y"
chk "1 waited on c1 only"   "$(waited_on)"                    "c1 "
chk "1 committed"           "$(saw 'hex_config -p bootstrap')" "y"
chk "1 peer bring-up"       "$(master_ran)"                   "n"
chk "1 bootup done"         "$(saw 'power_bootup_mark done')" "y"
chk "1 mode cleared"        "$(cat $TMP/boot_mode)"           ""

# 1b. no override: c1 is master in the foreground
rm -f $TMP/override $TMP/committed_*
COMMIT_AT=0 ; boot c1
chk "1b master bring-up"    "$(master_ran)"                   "y"
chk "1b no wait"            "$(waited_on)"                    ""

# 2. override names this node while it waits: master bring-up
rm -f $TMP/override $TMP/committed_*
COMMIT_AT=0 SWITCH_AT=2 SWITCH_TO=c2 ; boot c2
chk "2 committed"           "$(saw 'hex_config -p bootstrap')" "y"
chk "2 master bring-up"     "$(master_ran)"                   "y"
chk "2 roll advance"        "$(saw 'power_roll_advance c2')"  "y"
chk "2 bootup done"         "$(saw 'power_bootup_mark done')" "y"
chk "2 mode cleared"        "$(cat $TMP/boot_mode)"           ""

# 3. override names a peer: wait on that peer's commit instead
rm -f $TMP/override $TMP/committed_*
COMMIT_AT=4 COMMIT_HOST=c3 SWITCH_AT=2 SWITCH_TO=c3 ; boot c2
chk "3 waited on c1 then c3" "$(waited_on)"                   "c1 c3 "
chk "3 committed after c3"  "$(saw 'hex_config -p bootstrap')" "y"
chk "3 peer bring-up"       "$(master_ran)"                   "n"

# 4. old master returns while an override is in effect: joins as a peer
rm -f $TMP/override $TMP/committed_* ; echo c3 > $TMP/peer_override ; touch $TMP/committed_c3
COMMIT_AT=0 SWITCH_AT=0 ; boot c1
chk "4 adopted"             "$(cat $TMP/override)"            "c3"
chk "4 waited on c3"        "$(waited_on)"                    "c3 "
chk "4 peer bring-up"       "$(master_ran)"                   "n"
chk "4 committed"           "$(saw 'hex_config -p bootstrap')" "y"

# 5. compute, master c1 dead, override c3 on a peer: adopts it, commits after c3
rm -f $TMP/override $TMP/committed_* $TMP/dead_* ; touch $TMP/committed_c3 $TMP/committed_c2 $TMP/dead_c1
boot p1 compute
chk "5 adopt before commit" "$(grep -n 'power_master_override_adopt\|hex_config -p' $TMP/calls | tail -2 | cut -d' ' -f2 | tr '\n' ' ')" "power_master_override_adopt -p "
chk "5 adopted"             "$(cat $TMP/override)"            "c3"
chk "5 waited on c3"        "$(waited_on)"                    "c3 "
chk "5 committed"           "$(saw 'hex_config -p bootstrap')" "y"
rm -f $TMP/peer_override

# 6. compute, non-master c2 dead: waits only until the master commits
rm -f $TMP/override $TMP/committed_* $TMP/dead_* ; touch $TMP/committed_c3 $TMP/dead_c2
COMMIT_AT=3 COMMIT_HOST=c1 SWITCH_AT=0 ; boot p1 compute
chk "6 waited on c1"        "$(waited_on)"                    "c1 "
chk "6 waited for c1 commit" "$(cat $TMP/sleeps)"             "3"
chk "6 committed"           "$(saw 'hex_config -p bootstrap')" "y"
chk "6 bootup done"         "$(saw 'power_bootup_mark done')" "y"

# 7. compute, master c1 dead: follows an override set while it waits
rm -f $TMP/override $TMP/committed_* $TMP/dead_* ; touch $TMP/committed_c2 $TMP/dead_c1
COMMIT_AT=4 COMMIT_HOST=c3 SWITCH_AT=2 SWITCH_TO=c3 ; boot p1 compute
chk "7 waited on c1 then c3" "$(waited_on)"                   "c1 c3 "
chk "7 waited for c3 commit" "$(cat $TMP/sleeps)"             "4"
chk "7 committed"           "$(saw 'hex_config -p bootstrap')" "y"

# 8. compute, all controls up: still waits for every control's commit
rm -f $TMP/override $TMP/committed_* $TMP/dead_* ; touch $TMP/committed_c1 $TMP/committed_c3
COMMIT_AT=2 COMMIT_HOST=c2 SWITCH_AT=0 ; boot p1 storage
chk "8 waited for c2 commit" "$(cat $TMP/sleeps)"             "2"
chk "8 committed"           "$(saw 'hex_config -p bootstrap')" "y"
rm -f $TMP/committed_* $TMP/dead_*

echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: bootstrap master override" ; exit 0 ; } || exit 1
