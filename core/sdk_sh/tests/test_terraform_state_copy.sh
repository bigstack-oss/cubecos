#!/bin/bash
#
# Unit test for the local state copy terraform-action.sh (../../terraform/scripts) keeps for
# cubectl to push back into a recreated cluster: an apply writes it to terraform.tfstate.etcd,
# never to terraform.tfstate, where init -reconfigure takes it for local state to migrate; and
# a copy left at terraform.tfstate is moved before init, or dropped when empty.
#
# Self-contained: runs a copy of the script with its absolute paths pointed into a temp dir and
# terraform and cubectl mocked. ROOT selects the tree to test (default: this one).
# Run: bash test_terraform_state_copy.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=${ROOT:-$DIR/../../..}
T=$(mktemp -d)
trap 'rm -rf $T' EXIT

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

WD=$T/var/lib/terraform
mkdir -p $T/bin $T/state $WD
# terraform: init notes whether a local state file sits in the working dir; state pull prints
# the state in etcd
cat > $T/bin/terraform <<EOS
#!/bin/sh
echo "terraform \$*" >> $T/log
case "\$*" in
    *" init "*) [ -e $WD/terraform.tfstate ] && echo "init saw terraform.tfstate" >> $T/log ;;
    *"state pull") echo '{"serial": 7}' ;;
esac
exit 0
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
# enforce etcd TLS, so init runs with -reconfigure
mkdir -p $T/pki && touch $T/pki/ca.crt
# an HA node, so an apply rsyncs the working dir to the other controls
touch $T/settings.cluster.json

sed -e "s#/etc/etcd-pki#$T/pki#g" -e "s#/etc/appliance/state#$T/state#g" \
    -e "s#/etc/settings.cluster.json#$T/settings.cluster.json#g" \
    -e "s#/usr/local/bin/terraform #$T/bin/terraform #g" -e "s#/var/lib/terraform#$WD#g" \
    -e "s#^\(\s*\)cubectl #\1$T/bin/cubectl #" \
    $ROOT/core/terraform/scripts/terraform-action.sh > $T/terraform-action.sh

tf(){ : > $T/log ; bash $T/terraform-action.sh "$@" </dev/null >/dev/null 2>&1 ; }
content(){ [ -e "$1" ] && cat "$1" || echo absent ; }
reset(){ rm -f $WD/terraform.tfstate $WD/terraform.tfstate.etcd ; }

reset ; tf apply -auto-approve
chk "apply writes the copy"             "$(content $WD/terraform.tfstate.etcd)" '{"serial": 7}'
chk "apply leaves no terraform.tfstate" "$(content $WD/terraform.tfstate)"      absent
chk "apply rsyncs the working dir"      "$(grep -c "cubectl node rsync --role=control $WD/" $T/log)" 1

reset ; echo old > $WD/terraform.tfstate.etcd ; tf state list
chk "other commands keep the copy"      "$(content $WD/terraform.tfstate.etcd)" old

reset ; echo '{"serial": 3}' > $WD/terraform.tfstate ; tf state list
chk "a copy at the old path moves"      "$(content $WD/terraform.tfstate.etcd)" '{"serial": 3}'
chk "init sees no terraform.tfstate"    "$(grep -c 'init saw' $T/log)"          0
chk "init still reconfigures"           "$(grep -c ' init -upgrade -reconfigure ' $T/log)" 1

reset ; echo old > $WD/terraform.tfstate.etcd ; echo '{"serial": 9}' > $WD/terraform.tfstate ; tf state list
chk "it replaces an older copy"         "$(content $WD/terraform.tfstate.etcd)" '{"serial": 9}'

reset ; echo old > $WD/terraform.tfstate.etcd ; : > $WD/terraform.tfstate ; tf state list
chk "an empty one is dropped"           "$(content $WD/terraform.tfstate)"      absent
chk "and the copy stays"                "$(content $WD/terraform.tfstate.etcd)" old
chk "init sees no empty file either"    "$(grep -c 'init saw' $T/log)"          0

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
