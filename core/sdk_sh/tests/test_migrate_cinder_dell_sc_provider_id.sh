#!/bin/bash
#
# Unit test for migrate_cinder_dell_sc_provider_id in ../modules/sdk_migrate.sh: a
# one-time migration that repairs the provider_id of the Dell SC volumes a move away and
# back left pointing at a deleted array volume (#2422). Only the master control works;
# only backends whose volume_driver is the SC FC or iSCSI driver are read; a backend with
# nothing to repair is read and not written; a failed read or write leaves the marker
# unset so the next commit retries. The SQL itself is not exercised: it needs a cinder
# database. Fakes the DB and the backend files; needs no cluster.
#   Run: bash test_migrate_cinder_dell_sc_provider_id.sh
#
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); trap 'rm -rf $T' EXIT
sed -n "/^migrate_cinder_dell_sc_provider_id()/,/^}/p" $D/../modules/sdk_migrate.sh |
    sed -e "s|/etc/cinder/backends|$T/backends|" > $T/fn.sh
source $T/fn.sh
mkdir -p $T/state
FAILS=0
check() { if [ "$2" = "$3" ] ; then echo "ok   $1" ; else echo "FAIL $1: got $2 want $3" ; FAILS=$((FAILS+1)) ; fi ; }
STATE_DIR=$T/state; HOSTNAME=c1
log_info() { echo info >> $T/log; }; log_warning() { echo warn >> $T/log; }
CONTROL=1; is_control_node() { [ $CONTROL = 1 ]; }
MASTER=c1; HEX_SDK=fake_sdk; fake_sdk() { [ "$1" = cube_master_control ] && echo $MASTER; }
# the DB: each statement is recorded as <S|U>:<backend it names>
ROWS=""; READ=ok; WRITE=ok
MYSQL=db
db() {
    local q="$*" b
    b=$(echo "$q" | sed -n "s/.*@', -1) = '\([^']*\)'.*/\1/p" | head -1)
    case "$q" in
        *"SELECT v.id"*) echo "S:$b" >> $T/sql; [ $READ = ok ] || return 1; [ -n "$ROWS" ] && printf '%b\n' "$ROWS"; return 0 ;;
        *UPDATE*)        echo "U:$b" >> $T/sql; [ $WRITE = ok ] ;;
    esac
}
backend() {  # name driver
    printf '[%s]\nvolume_backend_name = %s\nvolume_driver = %s\nsan_ip = 10.0.0.1\n' $1 $1 $2 > $T/backends/ext_storage_$1.conf
}
SC_FC=cinder.volume.drivers.dell_emc.sc.storagecenter_fc.SCFCDriver
SC_ISCSI=cinder.volume.drivers.dell_emc.sc.storagecenter_iscsi.SCISCSIDriver
run() { rm -rf $T/backends $T/sql $T/log; mkdir -p $T/backends; "$@"
        migrate_cinder_dell_sc_provider_id
        echo "marker=$([ -f $T/state/cinder_dell_sc_provider_id_migrated ] && echo y || echo n)" \
             "sql=$(cat $T/sql 2>/dev/null | tr '\n' ' ')info=$(cat $T/log 2>/dev/null | grep -c info)" \
             "warn=$(cat $T/log 2>/dev/null | grep -c warn)"
        rm -f $T/state/*; }

ROWS="v1 364940.1491 364940.1492"
check "a stale SC volume: read, repaired, logged, marked" \
    "$(run backend dell-fc $SC_FC)" "marker=y sql=S:dell-fc U:dell-fc info=1 warn=0"
check "every SC backend, the iSCSI one included" \
    "$(run eval "backend dell-fc $SC_FC; backend dell-is $SC_ISCSI")" \
    "marker=y sql=S:dell-fc U:dell-fc S:dell-is U:dell-is info=2 warn=0"
check "other drivers are not touched" \
    "$(run eval "backend pure cinder.volume.drivers.pure.PureFCDriver; backend nfs cinder.volume.drivers.nfs.NfsDriver")" \
    "marker=y sql=info=0 warn=0"
ROWS=""
check "nothing stale: read, not written, marked" \
    "$(run backend dell-fc $SC_FC)" "marker=y sql=S:dell-fc info=0 warn=0"
check "no external backend: marked" "$(run :)" "marker=y sql=info=0 warn=0"
ROWS="v1 364940.1491 364940.1492"; READ=fail
check "the read fails: not written, not marked" \
    "$(run backend dell-fc $SC_FC)" "marker=n sql=S:dell-fc info=0 warn=1"
READ=ok; WRITE=fail
check "the write fails: not marked" \
    "$(run backend dell-fc $SC_FC)" "marker=n sql=S:dell-fc U:dell-fc info=0 warn=1"
WRITE=ok; MASTER=c2
check "not the master: marked, no SQL" "$(run backend dell-fc $SC_FC)" "marker=y sql=info=0 warn=0"
MASTER=c1; CONTROL=0
check "not a control: marked, no SQL" "$(run backend dell-fc $SC_FC)" "marker=y sql=info=0 warn=0"
CONTROL=1; rm -rf $T/sql; touch $T/state/cinder_dell_sc_provider_id_migrated
migrate_cinder_dell_sc_provider_id
check "already migrated: does nothing" "$(cat $T/sql 2>/dev/null)" ""

[ $FAILS -eq 0 ] && echo "PASS" || { echo "$FAILS FAILED"; exit 1; }
