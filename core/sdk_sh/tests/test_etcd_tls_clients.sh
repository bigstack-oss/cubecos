#!/bin/bash
#
# Unit test for the shell clients of cube's etcd: $ETCDCTL (../modules.pre/sdk_01-var-static.sh),
# etcdctl-cube.sh (../../cubectl/scripts) and terraform-action.sh (../../terraform/scripts).
# Each dials https with the client certificate only when the node enforces etcd TLS -- the
# PKI is in place and the rolling-upgrade compat marker is not -- and plain http otherwise.
#
# Self-contained: runs copies of the scripts with their absolute paths pointed into a temp dir
# and etcdctl, terraform, cubectl mocked. ROOT selects the tree to test (default: this one).
# Run: bash test_etcd_tls_clients.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=${ROOT:-$DIR/../../..}
T=$(mktemp -d)
trap 'rm -rf $T' EXIT

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

mkdir -p $T/bin $T/state $T/var/lib/terraform
cat > $T/bin/etcdctl <<EOS
#!/bin/sh
echo "etcdctl \$*" >> $T/log
EOS
cat > $T/bin/terraform <<EOS
#!/bin/sh
echo "terraform \$*" >> $T/log
EOS
cat > $T/bin/cubectl <<EOS
#!/bin/sh
echo "cubectl \$*" >> $T/log
EOS
# terraform-action.sh caps every terraform call with timeout(1); not every host has one
cat > $T/bin/timeout <<'EOS'
#!/bin/sh
while [ "${1#-}" != "$1" ] ; do [ "$1" = -k ] && shift ; shift ; done
shift
exec "$@"
EOS
chmod +x $T/bin/*
export PATH=$T/bin:$PATH
# the one-time state fixes in terraform-action.sh are done; only init and the command run
touch $T/state/terraform_keycloak_provider_migrated $T/state/terraform_mysql_module_dropped

redirect(){ sed -e "s#/etc/etcd-pki#$T/pki#g" -e "s#/etc/appliance/state#$T/state#g" \
                -e "s#/usr/local/bin/etcdctl#$T/bin/etcdctl#g" -e "s#/usr/local/bin/terraform #$T/bin/terraform #g" \
                -e "s#/var/lib/terraform#$T/var/lib/terraform#g" -e "s#^\(\s*\)cubectl #\1$T/bin/cubectl #" "$1" ; }
redirect $ROOT/core/sdk_sh/modules.pre/sdk_01-var-static.sh > $T/var-static.sh
redirect $ROOT/core/cubectl/scripts/etcdctl-cube.sh > $T/etcdctl-cube.sh
redirect $ROOT/core/terraform/scripts/terraform-action.sh > $T/terraform-action.sh

mode(){ # plain | compat | enforce
    rm -rf $T/pki $T/state/etcd_tls_compat
    [ "$1" = plain ] && return
    mkdir -p $T/pki && touch $T/pki/ca.crt
    [ "$1" = compat ] && touch $T/state/etcd_tls_compat
    return 0
}
etcdctl_var(){ ( PROG=test ; HOSTNAME=cc1 ; HEX_STATE_DIR=/etc/appliance/state ; source $T/var-static.sh ; echo "$ETCDCTL" | sed "s#$T#@#g" ) ; }
cube(){ : > $T/log ; sh $T/etcdctl-cube.sh get k ; sed "s#$T#@#g" $T/log ; }
tf_init(){ : > $T/log ; bash $T/terraform-action.sh state list 2>/dev/null ; grep ' init ' $T/log | sed "s#$T#@#g" ; }

CERTS="--cacert=@/pki/ca.crt --cert=@/pki/client.crt --key=@/pki/client.key"

for m in plain compat ; do
    mode $m
    chk "$m ETCDCTL"           "$(etcdctl_var)" "@/bin/etcdctl --endpoints=cc1:12379"
    chk "$m etcdctl-cube.sh"   "$(cube)"        "etcdctl --endpoints=127.0.0.1:12379 get k"
    chk "$m terraform init"    "$(tf_init)"     "terraform -chdir=@/var/lib/terraform init -upgrade"
done

mode enforce
chk "enforce ETCDCTL"          "$(etcdctl_var)" "@/bin/etcdctl --endpoints=https://cc1:12379 $CERTS"
chk "enforce etcdctl-cube.sh"  "$(cube)"        "etcdctl --endpoints=https://127.0.0.1:12379 $CERTS get k"
chk "enforce terraform init"   "$(tf_init)" \
    "terraform -chdir=@/var/lib/terraform init -upgrade -reconfigure -backend-config=@/pki/terraform-backend.hcl"
chk "enforce terraform runs the command" "$(grep -c 'terraform -chdir=.* state list$' $T/log)" "1"

# a stray marker without the PKI is plain
mode plain ; touch $T/state/etcd_tls_compat
chk "marker only ETCDCTL"      "$(etcdctl_var)" "@/bin/etcdctl --endpoints=cc1:12379"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
