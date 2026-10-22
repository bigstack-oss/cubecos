#!/bin/bash
#
# Unit test for etcd_tls_migrate_prepare (../modules/sdk_etcd.sh): the migrate hook in
# config_cluster.cpp calls it with the previous root, and it puts the node in etcd TLS
# compat unless that root already enforced TLS.
#
# Self-contained: extracts the function and builds previous roots under a temp dir.
# Run: bash test_etcd_tls_migrate.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_etcd.sh"
T=$(mktemp -d)
trap 'rm -rf $T' EXIT

body="$(awk '/^etcd_tls_migrate_prepare\(\)/{p=1} p{print} p&&/^}/{exit}' "$SRC")"
[ -n "$body" ] || { echo "FAIL: etcd_tls_migrate_prepare not extracted"; exit 1; }
eval "$body"

ETCD_PKI_DIR=/etc/etcd-pki
ETCD_TLS_COMPAT_MARK=$T/now/etc/appliance/state/etcd_tls_compat

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

PLAIN='listen-client-urls: http://127.0.0.1:12379
listen-peer-urls: http://10.0.0.11:12380'
COMPAT='client-transport-security:
    cert-file: /etc/etcd-pki/member.crt
peer-transport-security:
    cert-file: /etc/etcd-pki/member.crt'
ENFORCE='client-transport-security:
    cert-file: /etc/etcd-pki/member.crt
    client-cert-auth: true
peer-transport-security:
    allowed-cn:
        - etcd-member
    client-cert-auth: true'

# prev <conf content or -> <pki y|n> <marker y|n>; prints whether the marker got placed
run(){
    local prev=$T/prev
    rm -rf $prev $T/now
    mkdir -p $prev/etc/etcd
    [ "$1" = - ] || printf '%s\n' "$1" > $prev/etc/etcd/etcd.conf.yml
    [ "$2" = y ] && { mkdir -p $prev$ETCD_PKI_DIR ; touch $prev$ETCD_PKI_DIR/ca.crt ; }
    [ "$3" = y ] && { mkdir -p $(dirname $prev$ETCD_TLS_COMPAT_MARK) ; touch $prev$ETCD_TLS_COMPAT_MARK ; }
    etcd_tls_migrate_prepare $prev ; local rc=$?
    echo "$rc $([ -e $ETCD_TLS_COMPAT_MARK ] && echo marker || echo none)"
}

chk "1 control from a plain release"         "$(run "$PLAIN" n n)"   "0 marker"
chk "2 compute from a plain release"         "$(run - n n)"          "0 marker"
chk "3 control from an enforcing release"    "$(run "$ENFORCE" y n)" "0 none"
chk "4 compute from an enforcing release"    "$(run - y n)"          "0 none"
chk "5 roll whose ladder never completed"    "$(run "$COMPAT" y y)"  "0 marker"
chk "6 compute, ladder never completed"      "$(run - y y)"          "0 marker"
chk "7 control left in compat, marker lost"  "$(run "$COMPAT" y n)"  "0 marker"
chk "8 plain config next to a stray PKI"     "$(run "$PLAIN" y n)"   "0 marker"

# 9. the C++ hook hands the previous root to exactly this function
CPP="$DIR/../../modules/config_cluster.cpp"
chk "9 hook calls the sdk"     "$(grep -c 'HEX_SDK " etcd_tls_migrate_prepare %s", prevRootDir' "$CPP")" "1"
chk "9 hook registered"        "$(grep -c '^CONFIG_MIGRATE(cluster, MigrateEtcdTls);' "$CPP")" "1"
chk "9 PKI carried over"       "$(grep -c '^CONFIG_MIGRATE(cluster, "/etc/etcd-pki");' "$CPP")" "1"
chk "9 module installed"       "$(grep -c 'modules/sdk_etcd.sh$' "$DIR/../../main/cube.mk")" "1"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
