#!/bin/bash
#
# Unit test for the chassis-first, central-last OVN machinery in ../modules/sdk_ovn.sh:
# which nodes enter the carried-central mode at the A/B migrate, what a node does with a
# carried central's databases when the image has no such central, the chassis gate that
# holds the switch, and the per-node convert/restore the switch is built from. The
# carried minor is 23.03, as 3.1.20 left it.
#
# Self-contained: extracts just these functions and mocks hex_tuning, ovsdb-tool,
# cubectl, remote_run and the local northd, so it needs no cluster and no OVN. A mock
# database file's first line is its schema version.  Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_ovn.sh"
T=$(mktemp -d)

export OVN_COMPAT_VER=23.03 OVN_COMPAT_DIR=$T/opt/ovn-23.03 OVN_COMPAT_DB_DIR=$T/etc/ovn/compat-23.03
export OVN_DB_DIR=$T/etc/ovn OVN_SCHEMA_DIR=$T/usr/share/ovn
for fn in ovn_central_compat_active ovn_central_compat_enter ovn_chassis_version_uniform \
          ovn_central_convert_local ovn_central_restore_local ; do
    body="$(awk -v f="^${fn}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done

LOG=$T/log
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
saw(){ grep -qe "$1" "$LOG" && echo y || echo n; }
yes_if(){ "$@" && echo y || echo n; }

# --- mocks
log_info(){ echo "info $*" >> "$LOG" ; }
log_warning(){ echo "warning $*" >> "$LOG" ; }
log_error(){ echo "error $*" >> "$LOG" ; }
mkdir -p $T/bin && cat > $T/bin/hex_tuning <<'EOS'
v=$(awk -F' = ' -v k="$2" '$1==k{print $2}' "$1")
eval "T_$(echo $2 | tr . _)=\"\$v\""
EOS
PATH=$T/bin:$PATH
FAIL_CONVERT=""
ovsdb-tool(){
    case $1 in
        db-version|schema-version) head -1 "$2" ;;
        compact) [ -e "$2" ] ;;
        convert) [ -n "$FAIL_CONVERT" ] && [[ "$2" == *"$FAIL_CONVERT"* ]] && return 1
                 { head -1 "$3" ; tail -n +2 "$2" ; } > "$4" ;;
    esac
}
NORTHD="ovn-northd 24.03.9"
ovn-northd(){ [ -n "$NORTHD" ] && echo "$NORTHD" ; }
CHASSIS="cc1 cc2 cc3"
declare -A VER=( [cc1]=24.03.9 [cc2]=24.03.9 [cc3]=24.03.9 )
cubectl(){ printf '%s\n' $CHASSIS | jq -Rn '[inputs | {hostname: .}]' ; }
remote_run(){ local h=$1 ; [ -n "${VER[$h]:-}" ] && echo "ovn-controller ${VER[$h]}" ; }

# --- a node as the A/B migrate leaves it: 23.03 databases copied into /etc/ovn
mkdir -p $OVN_COMPAT_DIR/share/ovn $OVN_SCHEMA_DIR $T/prev/etc
echo 7.0.0 > $OVN_COMPAT_DIR/share/ovn/ovn-nb.ovsschema ; echo 20.27.0 > $OVN_COMPAT_DIR/share/ovn/ovn-sb.ovsschema
echo 7.3.0 > $OVN_SCHEMA_DIR/ovn-nb.ovsschema          ; echo 20.33.0 > $OVN_SCHEMA_DIR/ovn-sb.ovsschema
node(){   # <role> <ha> <nb-version> <sb-version>
    rm -rf $OVN_DB_DIR ; mkdir -p $OVN_DB_DIR ; : > "$LOG"
    printf 'cubesys.role = %s\ncubesys.ha = %s\n' "$1" "$2" > $T/prev/etc/settings.txt
    printf '%s\nnb-rows\n' "$3" > $OVN_DB_DIR/ovnnb_db.db
    printf '%s\nsb-rows\n' "$4" > $OVN_DB_DIR/ovnsb_db.db
}

# 1. an HA control node that carried 23.03 databases takes them for the 23.03 central
node control-converged true 7.0.0 20.27.0
ovn_central_compat_enter $T/prev
chk "1 enters the 23.03 mode"       "$(yes_if ovn_central_compat_active)" "y"
chk "1 default nb moved away"       "$(yes_if test -e $OVN_DB_DIR/ovnnb_db.db)" "n"
chk "1 default sb moved away"       "$(yes_if test -e $OVN_DB_DIR/ovnsb_db.db)" "n"
chk "1 sb kept, unconverted"        "$(head -1 $OVN_COMPAT_DB_DIR/ovnsb_db.db)" "20.27.0"
chk "1 logs it"                     "$(saw 'info ovn_central_compat_enter')" "y"

# 2. edge-core and moderator carry the control bit and run ovndb_servers too
for r in edge-core moderator control ; do
    node $r true 7.0.0 20.27.0 ; ovn_central_compat_enter $T/prev
    chk "2 $r enters" "$(yes_if ovn_central_compat_active)" "y"
done

# 3. nothing to do: already 24.03, not a control node, not HA, no 23.03 tree
node control-converged true 7.3.0 20.33.0 ; ovn_central_compat_enter $T/prev
chk "3 24.03 databases stay"        "$(yes_if ovn_central_compat_active)" "n"
node control-converged true 7.0.0 20.33.0 ; ovn_central_compat_enter $T/prev
chk "3 mixed versions stay"         "$(yes_if ovn_central_compat_active)" "n"
node compute true 7.0.0 20.27.0 ; ovn_central_compat_enter $T/prev
chk "3 compute stays"               "$(yes_if ovn_central_compat_active)" "n"
node control-converged false 7.0.0 20.27.0 ; ovn_central_compat_enter $T/prev
chk "3 non-HA stays"                "$(yes_if ovn_central_compat_active)" "n"
node control-converged true 7.0.0 20.27.0 ; mv $OVN_COMPAT_DIR $T/hidden
ovn_central_compat_enter $T/prev
chk "3 no 23.03 tree stays"         "$(yes_if ovn_central_compat_active)" "n"
mv $T/hidden $OVN_COMPAT_DIR

# 4. entering twice never overwrites the 23.03 copy with a later default database
node control-converged true 7.0.0 20.27.0 ; ovn_central_compat_enter $T/prev
printf '7.0.0\nstray\n' > $OVN_DB_DIR/ovnnb_db.db ; printf '20.27.0\nstray\n' > $OVN_DB_DIR/ovnsb_db.db
ovn_central_compat_enter $T/prev
chk "4 23.03 copy untouched"        "$(tail -1 $OVN_COMPAT_DB_DIR/ovnnb_db.db)" "nb-rows"

# 5. the gate: every chassis on this node's OVN minor, read from the running daemon
: > "$LOG"
chk "5 all chassis 24.03"           "$(yes_if ovn_chassis_version_uniform)" "y"
VER[cc2]=23.03.1
chk "5 a 23.03 chassis holds"       "$(yes_if ovn_chassis_version_uniform)" "n"
chk "5 names the holdout"           "$(saw 'cc2 runs ovn-controller 23.03')" "y"
VER[cc2]=""
chk "5 unreachable holds"           "$(yes_if ovn_chassis_version_uniform)" "n"
VER[cc2]=24.03.9 ; NORTHD=""
chk "5 no local northd holds"       "$(yes_if ovn_chassis_version_uniform)" "n"
NORTHD="ovn-northd 24.03.9"

# 6. convert: default location gets the 24.03 databases, the 23.03 ones become the backup
node control-converged true 7.0.0 20.27.0 ; ovn_central_compat_enter $T/prev
ovn_central_convert_local 20260924-000000 ; rc=$?
BK=$OVN_DB_DIR/backup-23.03-20260924-000000
chk "6 converts"                    "$rc" "0"
chk "6 nb now 24.03"                "$(head -1 $OVN_DB_DIR/ovnnb_db.db)" "7.3.0"
chk "6 sb now 24.03"                "$(head -1 $OVN_DB_DIR/ovnsb_db.db)" "20.33.0"
chk "6 rows carried"                "$(tail -1 $OVN_DB_DIR/ovnsb_db.db)" "sb-rows"
chk "6 backup is the 23.03 copy"    "$(head -1 $BK/ovnnb_db.db)" "7.0.0"
chk "6 leaves the 23.03 mode"       "$(yes_if ovn_central_compat_active)" "n"
chk "6 second run is a no-op"       "$(yes_if ovn_central_convert_local 20260924-000001)" "y"

# 7. a default database the node already had is set aside, not lost
node control-converged true 7.0.0 20.27.0 ; ovn_central_compat_enter $T/prev
printf '7.3.0\nold-default\n' > $OVN_DB_DIR/ovnnb_db.db
ovn_central_convert_local 20260924-000002
chk "7 old default kept aside"      "$(tail -1 $OVN_DB_DIR/backup-23.03-20260924-000002/ovnnb_db.db.default)" "old-default"

# 8. a failed convert is undone: 23.03 mode back, original rows, no half-converted default
node control-converged true 7.0.0 20.27.0 ; ovn_central_compat_enter $T/prev
FAIL_CONVERT=ovnsb_db.db
ovn_central_convert_local 20260924-000003 ; rc=$?
FAIL_CONVERT=""
chk "8 reports the failure"         "$([ $rc -ne 0 ] && echo y || echo n)" "y"
ovn_central_restore_local 20260924-000003
chk "8 back in the 23.03 mode"      "$(yes_if ovn_central_compat_active)" "y"
chk "8 23.03 nb restored"           "$(head -1 $OVN_COMPAT_DB_DIR/ovnnb_db.db)" "7.0.0"
chk "8 no converted nb left"        "$(yes_if test -e $OVN_DB_DIR/ovnnb_db.db)" "n"

# 9. an image with no 23.03 central (epoxy): a node the previous roll left on its 23.03
#    central converts the databases at the migrate instead of handing them to pacemaker
node control-converged true 7.0.0 20.27.0 ; ovn_central_compat_enter $T/prev
mv $OVN_COMPAT_DIR $T/hidden ; : > "$LOG"
ovn_central_compat_enter $T/prev ; rc=$?
chk "9 converts"                    "$rc" "0"
chk "9 leaves the 23.03 mode"       "$(yes_if ovn_central_compat_active)" "n"
chk "9 nb now 24.03"                "$(head -1 $OVN_DB_DIR/ovnnb_db.db)" "7.3.0"
chk "9 sb rows carried"             "$(tail -1 $OVN_DB_DIR/ovnsb_db.db)" "sb-rows"
chk "9 23.03 copy kept as backup"   "$(ls -d $OVN_DB_DIR/backup-23.03-* 2>/dev/null | wc -l | tr -d ' ')" "1"
chk "9 warns"                       "$(saw 'warning ovn_central_compat_enter')" "y"

# 10. ... and a failed conversion there puts the 23.03 databases back and says so
node control-converged true 7.0.0 20.27.0 ; mv $T/hidden $OVN_COMPAT_DIR
ovn_central_compat_enter $T/prev ; mv $OVN_COMPAT_DIR $T/hidden ; : > "$LOG"
FAIL_CONVERT=ovnsb_db.db
ovn_central_compat_enter $T/prev ; rc=$?
FAIL_CONVERT=""
chk "10 reports the failure"        "$([ $rc -ne 0 ] && echo y || echo n)" "y"
chk "10 23.03 databases restored"   "$(head -1 $OVN_COMPAT_DB_DIR/ovnsb_db.db)" "20.27.0"
chk "10 no converted nb left"       "$(yes_if test -e $OVN_DB_DIR/ovnnb_db.db)" "n"
chk "10 logs the error"             "$(saw 'error ovn_central_compat_enter')" "y"

# 11. no 23.03 central and nothing carried: the migrate touches nothing
node control-converged true 7.3.0 20.33.0 ; ovn_central_compat_enter $T/prev ; rc=$?
chk "11 no-op"                      "$rc" "0"
chk "11 default nb untouched"       "$(head -1 $OVN_DB_DIR/ovnnb_db.db)" "7.3.0"
chk "11 no backup made"             "$(ls -d $OVN_DB_DIR/backup-* 2>/dev/null | wc -l | tr -d ' ')" "0"
mv $T/hidden $OVN_COMPAT_DIR

rm -rf "$T"
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: ovn central compat" ; exit 0 ; } || exit 1
