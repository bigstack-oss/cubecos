#!/bin/bash
#
# Unit test for os_import_volume and os_volume_meta_sync in ../modules/sdk_os.sh: the DR
# site takes the service uuid from the one live cinder-volume service on the target host,
# whatever else the services table holds, and a failed import is reported, not swallowed.
# Stubs mariadb, openstack, sshpass and the user/project lookups.
# Run: bash test_os_import_volume.sh
#
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); trap 'rm -rf $T' EXIT
for f in os_import_volume os_volume_meta_sync ; do
    sed -n "/^$f()/,/^}/p" $D/../modules/sdk_os.sh
done > $T/fn.sh
source $T/fn.sh
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

MakeTemp(){ mktemp $T/tmp.XXXX; }
os_get_user_id_by_name(){ [ "$1" = admin ] && echo u-1; }
os_get_project_id_by_name(){ [ "$1" = admin ] && echo p-1; }
OPENSTACK=openstack_stub
openstack_stub(){
    case "$1 $2 $3" in
        "volume type show") [ "$4" = CubeStorage ] && echo "| id | t-1 |" ;;
        "volume show "*) echo '{"user_id":"u-1","os-vol-tenant-attr:tenant_id":"p-1"}' ;;
        "user list "*) echo "u-1 admin" ;;
        "project list "*) echo "p-1 admin" ;;
    esac; }
# the service query: answer with $SERVICES, record what was asked
/usr/bin/mariadb(){ echo "$*" > $T/query; [ -n "$SERVICES" ] && printf '%s\n' $SERVICES; return 0; }
# the import
mariadb(){ cat > $T/imported; return ${IMPORT_RC:-0}; }

META=$T/meta.sql
echo "REPLACE INTO volumes VALUES ('v-1','%user_id%','%proj_id%','%host%','%type_id%','%service_uuid%');" > $META
run(){ rm -f $T/imported; os_import_volume "$@" $META 2>$T/err; echo $?; }

# 1. one live service on the host: imported with its uuid
SERVICES=s-ceph
chk "1 rc"                 "$(run admin admin 'cube@ceph#ceph' CubeStorage)" 0
chk "1 imported"           "$(cat $T/imported)" "REPLACE INTO volumes VALUES ('v-1','u-1','p-1','cube@ceph#ceph','t-1','s-ceph');"
chk "1 asks for the host"  "$(grep -c "host = 'cube@ceph' and deleted = 0" $T/query)" 1

# 2. more than one row comes back: refused, nothing imported
SERVICES="s-ceph s-other"
chk "2 rc"                 "$(run admin admin 'cube@ceph#ceph' CubeStorage)" 1
chk "2 nothing imported"   "$(ls $T/imported 2>/dev/null)" ""
chk "2 says why"           "$(grep -c 'expected one live cinder-volume service on cube@ceph, found 2' $T/err)" 1

# 3. no live service on the host
SERVICES=""
chk "3 rc"                 "$(run admin admin 'cube@ceph#ceph' CubeStorage)" 1
chk "3 nothing imported"   "$(ls $T/imported 2>/dev/null)" ""

# 4. unknown project on the DR site: refused instead of importing an empty project id
SERVICES=s-ceph
chk "4 rc"                 "$(run admin nosuch 'cube@ceph#ceph' CubeStorage)" 1
chk "4 nothing imported"   "$(ls $T/imported 2>/dev/null)" ""
chk "4 says why"           "$(grep -c 'project nosuch' $T/err)" 1

# 5. the import fails on the peer: os_volume_meta_sync returns 3 with the peer's reason
os_export_volume(){ echo "-- meta" > $1; }
sshpass(){ shift 2; case "$1" in
        scp) return 0 ;;
        ssh) case "$*" in *os_import_volume*) echo "os_import_volume: expected one live cinder-volume service on cube@ceph, found 0" >&2; return 1 ;; esac ;;
    esac; return 0; }
out=$(os_volume_meta_sync 10.0.0.2 pw v-1); rc=$?
chk "5 rc"                 "$rc" 3
chk "5 peer reason shown"  "$(echo "$out" | grep -c 'found 0')" 1

echo "PASS=$pass FAIL=$fail"
[ $fail -eq 0 ]
