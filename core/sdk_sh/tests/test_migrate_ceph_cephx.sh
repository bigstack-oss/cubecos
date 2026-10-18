#!/bin/bash
#
# Unit test for migrate_ceph_cephx_cipher in ../modules/sdk_migrate.sh: it waits for the
# end of a roll, switches the mons' ciphers, rotates the client keys ceph lists as aes,
# brings every copy of them in line, and allows only aes256k last -- never before the
# keys and their copies are done, and without redoing a rotation on a later pass.
# Stubs ceph, hex_sdk, cubectl, remote_run, ceph-authtool and kubectl.
# Run: bash test_migrate_ceph_cephx.sh
#
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); trap 'rm -rf $T' EXIT
for f in migrate_ceph_cephx_cipher _migrate_cephx_field _migrate_cephx_copies migrate_ceph_cephx_csi_secrets ; do
    sed -n "/^$f()/,/^}/p" $D/../modules/sdk_migrate.sh
done > $T/fn.sh
source $T/fn.sh
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

mkdir -p $T/etc
ADMIN_KEYRING=$T/etc/ceph.client.admin.keyring
K8S_KEYRING=$T/etc/ceph.client.k8s.keyring
CEPHFS_CLIENT_AUTHKEY=$T/etc/admin.key
CALLS=$T/calls
CUBE_NODE_CONTROL_HOSTNAMES=(cc1 cc2 cc3)
log_info(){ :; }; log_warning(){ :; }
kr(){ printf '[client.%s]\n\tkey = %s\n' $1 $2 > $3; }
# like the real one: -p prints client.admin's key unless -n names another entity
ceph-authtool(){ local n=client.admin f; while [ $# -gt 0 ]; do case $1 in -p) ;; -n) n=$2; shift ;; *) f=$1 ;; esac; shift; done
    awk -v e="[$n]" '$0 == e {f=1; next} /^\[/ {f=0} f && /key = / {print $3}' "$f" 2>/dev/null; }

# an upgraded, unrotated cluster
reset(){
    SVC=aes PREF=aes ALLOWED=aes,aes256k KEY_admin=AQold-admin== KEY_k8s=AQold-k8s== TYPE_admin=aes TYPE_k8s=aes
    FINAL_RC=0 MDS_REL=squid ROTATE_RC=0 RSYNC_RC=0 EXEC_RC=0 RR_OK=cc1
    kr admin $KEY_admin $ADMIN_KEYRING; kr k8s $KEY_k8s $K8S_KEYRING; echo $KEY_admin > $CEPHFS_CLIENT_AUTHKEY
    : > $CALLS
}
ciphers(){ local o= c; for c in ${1//,/ }; do o+="{\"name\":\"$c\"},"; done; echo "[${o%,}]"; }
CEPH=ceph_stub
ceph_stub(){ echo "ceph $*" >> $CALLS
    case "$1 $2" in
        "mon dump") echo "{\"auth_service_cipher\":{\"name\":\"$SVC\"},\"auth_preferred_cipher\":{\"name\":\"$PREF\"},\"auth_allowed_ciphers\":$(ciphers $ALLOWED)}" ;;
        "mon set") case $3 in auth_service_cipher) SVC=$4 ;; auth_preferred_cipher) PREF=$4 ;; auth_allowed_ciphers) ALLOWED=$4 ;; esac ;;
        "health detail")
            local d= e
            for e in admin k8s; do [ "$(eval echo \$TYPE_$e)" = aes ] && d+="{\"message\":\"entity client.$e using insecure key type: aes\"},"; done
            [ -n "$d" ] && echo "{\"checks\":{\"AUTH_INSECURE_CLIENT_KEY_TYPE\":{\"detail\":[${d%,}]}}}" || echo '{"checks":{}}' ;;
        "auth rotate") [ $ROTATE_RC = 0 ] || return 1; eval KEY_${3#client.}=AQnew-${3#client.}== TYPE_${3#client.}=aes256k ;;
        "auth get-key") eval echo \$KEY_${3#client.} ;;
        "auth get") kr ${3#client.} $(eval echo \$KEY_${3#client.}) $5 ;;
    esac; }
HEX_SDK=sdk
sdk(){ echo "sdk $*" >> $CALLS
    case "$1" in
        ceph_finalize_release) return $FINAL_RC ;;
        ceph_tier_releases) [ "$2" = mds ] && printf '%s\n' $MDS_REL || echo squid ;;
    esac; }
cubectl(){ echo "cubectl $*" >> $CALLS; case "$2" in rsync) return $RSYNC_RC ;; exec) return $EXEC_RC ;; esac; }
remote_run(){ echo "rr $1" >> $CALLS; case " $RR_OK " in *" $1 "*) return 0 ;; esac; return 1; }
run(){ : > $CALLS; migrate_ceph_cephx_cipher >/dev/null 2>&1; RC=$?; }   # in this shell: the stubs keep their state
n(){ grep -c -- "$1" $CALLS; }
line(){ grep -n -m1 -- "$1" $CALLS | cut -d: -f1; }

# 1. the gate: nothing changes before the roll is done
reset; FINAL_RC=1
run; chk "1 release not finalized: retry" "$RC" 1
chk "1 no mon set"                     "$(n 'ceph mon set')" 0
reset; MDS_REL="reef squid"
run; chk "1 mixed mds tier: retry" "$RC" 1
chk "1 no rotation"                    "$(n 'auth rotate')" 0

# 2. the whole move, in order
reset
run; chk "2 upgraded cluster: done" "$RC" 0
chk "2 tickets aes256k"                "$SVC" aes256k
chk "2 new keys aes256k"               "$PREF" aes256k
chk "2 only aes256k allowed"           "$ALLOWED" aes256k
chk "2 both clients rotated"           "$(n 'auth rotate')" 2
chk "2 admin keyring has the new key"  "$(ceph-authtool -p $ADMIN_KEYRING)" AQnew-admin==
chk "2 k8s keyring has the new key"    "$(ceph-authtool -p -n client.k8s $K8S_KEYRING)" AQnew-k8s==
chk "2 cephfs secret has the new key"  "$(cat $CEPHFS_CLIENT_AUTHKEY)" AQnew-admin==
chk "2 three files pushed"             "$(n 'cubectl node rsync')" 3
chk "2 libvirt secret refreshed"       "$(n 'cubectl node exec')" 1
chk "2 csi secrets on a control"       "$(n 'rr cc1')" 1
chk "2 service cipher before rotation" "$([ $(line 'mon set auth_service_cipher') -lt $(line 'auth rotate') ] && echo y)" y
chk "2 aes dropped after the copies"   "$([ $(line 'mon set auth_allowed_ciphers') -gt $(line 'rr cc1') ] && echo y)" y
run; chk "2 a later pass does nothing" "$RC" 0
chk "2 ... and calls nothing else"     "$(grep -vc '^ceph mon dump' $CALLS)" 0

: > $CALLS; _migrate_cephx_copies >/dev/null 2>&1
chk "2 copies current: no keyring rewritten" "$(n 'auth get client')" 0

# 3. failures leave aes allowed, and the next pass finishes without rotating again
reset; ROTATE_RC=1
run; chk "3 rotation fails: retry" "$RC" 1
chk "3 aes still allowed"              "$ALLOWED" aes,aes256k
reset; RSYNC_RC=1
run; chk "3 push fails: retry" "$RC" 1
chk "3 aes still allowed (push)"       "$ALLOWED" aes,aes256k
RSYNC_RC=0
run; chk "3 next pass finishes" "$RC" 0
chk "3 no second rotation"             "$(n 'auth rotate')" 0
chk "3 ... but the copies are pushed"  "$(n 'cubectl node rsync')" 3
reset; EXEC_RC=1
run; chk "3 libvirt update fails: retry" "$RC" 1
chk "3 aes still allowed (libvirt)"    "$ALLOWED" aes,aes256k

# 4. the ceph-csi secrets: tried on each control until one has k3s
reset; RR_OK=cc2
run; chk "4 second control does it" "$RC" 0
chk "4 first control tried first"      "$([ $(line 'rr cc1') -lt $(line 'rr cc2') ] && echo y)" y
reset; RR_OK=none
run; chk "4 no control: retry" "$RC" 1
chk "4 aes still allowed (csi)"        "$ALLOWED" aes,aes256k

# 5. migrate_ceph_cephx_csi_secrets patches only the keys that differ
b64(){ printf %s "$1" | base64; }
KUBECTL=kubectl_stub
kubectl_stub(){ echo "kubectl $*" >> $CALLS
    case "$3 $4" in
        "get secret") [ "$6" = "-o" ] || return 0
            case "$2" in
                ceph-csi-rbd) echo "{\"data\":{\"userID\":\"$(b64 admin)\",\"userKey\":\"$(b64 $RBD_KEY)\"}}" ;;
                ceph-csi-cephfs) echo "{\"data\":{\"userKey\":\"$(b64 $FS_KEY)\",\"adminKey\":\"$(b64 $FS_KEY)\"}}" ;;
            esac ;;
        "patch secret") echo "$9" > $T/patch.$2 ;;
    esac; }
reset; kr admin AQnew-admin== $ADMIN_KEYRING; rm -f $T/patch.*
RBD_KEY=AQnew-admin== FS_KEY=AQold-admin==
chk "5 csi update passes"              "$(migrate_ceph_cephx_csi_secrets && echo 0 || echo 1)" 0
chk "5 current secret left alone"      "$(ls $T/patch.ceph-csi-rbd 2>/dev/null)" ""
chk "5 stale secret patched"           "$(jq -c . $T/patch.ceph-csi-cephfs)" '{"stringData":{"userKey":"AQnew-admin==","adminKey":"AQnew-admin=="}}'

echo "PASS=$pass FAIL=$fail"
[ $fail -eq 0 ]
