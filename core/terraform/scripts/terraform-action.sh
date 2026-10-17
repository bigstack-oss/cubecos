#!/bin/sh

export TF_CLI_CONFIG_FILE=/etc/cube/cos/terraform/configs/override.tfrc

pushd /tmp >/dev/null 2>&1
# The providers come only from this release's local mirror (override.tfrc), and each release
# builds its own. The lock file records the builds the last init saw, and cubectl node rsync
# copies it and .terraform/ between control nodes after every apply, so in a rolling upgrade a
# node can hold a lock written against the other release's builds. terraform then refuses its own
# mirror -- init with "doesn't match any of the checksums previously recorded", every other
# command, state pull included, with "Required plugins are not installed" -- until the lock goes.
# The image ships without one for the same reason (terraform.mk); drop it before anything runs,
# so init records the mirror this node has.
rm -f /var/lib/terraform/.terraform.lock.hcl
# The keycloak provider moved from mrparkers/keycloak to keycloak/keycloak, and only the new
# address is in the mirror. State written by a release on the old provider still names the
# old one for every keycloak resource, init cannot install it, and so every command fails --
# a -target=module.rancher apply included, since terraform loads every provider the state
# names. Rewrite it before init. The state lives in etcd and is shared by the control nodes,
# so whichever node runs first does it for all of them.
#
# The marker makes that a one-time check, as in sdk_migrate.sh: /etc/appliance/state is not
# carried across the A/B switch, so each new firmware looks once. It is set only once the
# shared state is known to be clean, so a state nobody could read is looked at again.
KEYCLOAK_PROVIDER_MIGRATED=/etc/appliance/state/terraform_keycloak_provider_migrated
if [ ! -f $KEYCLOAK_PROVIDER_MIGRATED ] ; then
    STATE=$(timeout -k 1s 60s /usr/local/bin/terraform -chdir=/var/lib/terraform state pull 2>/dev/null)
    if [ $? -eq 0 ] ; then
        if ! echo "$STATE" | grep -q 'registry.terraform.io/mrparkers/keycloak' ; then
            touch $KEYCLOAK_PROVIDER_MIGRATED
        elif timeout -k 1s 60s /usr/local/bin/terraform -chdir=/var/lib/terraform state replace-provider \
                -auto-approve registry.terraform.io/mrparkers/keycloak registry.terraform.io/keycloak/keycloak >&2 ; then
            touch $KEYCLOAK_PROVIDER_MIGRATED
        fi
    fi
fi
# The mysql module is gone -- the keycloak database is created with SQL now -- and so is
# terraform-providers/mysql from the mirror. State written by an earlier release still holds
# module.mysql, init cannot install its provider, and every command fails as above. Drop it
# from the state before init. state rm only edits the state: the MariaDB database and users
# stay. Same one-time marker as above.
MYSQL_MODULE_DROPPED=/etc/appliance/state/terraform_mysql_module_dropped
if [ ! -f $MYSQL_MODULE_DROPPED ] ; then
    STATE=$(timeout -k 1s 60s /usr/local/bin/terraform -chdir=/var/lib/terraform state pull 2>/dev/null)
    if [ $? -eq 0 ] ; then
        if ! echo "$STATE" | grep -q '"module": "module.mysql"' ; then
            touch $MYSQL_MODULE_DROPPED
        elif timeout -k 1s 60s /usr/local/bin/terraform -chdir=/var/lib/terraform state rm module.mysql >&2 ; then
            touch $MYSQL_MODULE_DROPPED
        fi
    fi
fi
# Only the command's own output goes to stdout. Callers parse it -- the rancher token comes from
# `state pull | jq` in cubectl's config_rancher and in hex_sdk -- so the steps before it, init
# above all, print to stderr.
timeout -k 1s 60s /usr/local/bin/terraform -chdir=/var/lib/terraform init -upgrade >&2
timeout -k 1s 60s /usr/local/bin/terraform -chdir=/var/lib/terraform "$@"
[ $? -eq 0 ] || exit 1

# A pushed state can predate the provider move -- a cluster re-IP pushes the local
# terraform.tfstate copy back in (cubectl config_cluster.go) -- so look at it again. Likewise
# for a pushed state that still holds module.mysql.
if [ "$1" == "state" ] && [ "$2" == "push" ]; then
    rm -f $KEYCLOAK_PROVIDER_MIGRATED $MYSQL_MODULE_DROPPED
fi

if [ "$1" == "apply" ] || [ "$1" == "destroy" ] || [ "$1" == "import" ]; then
    /usr/local/bin/terraform -chdir=/var/lib/terraform state pull > /var/lib/terraform/terraform.tfstate

    if [ -f /etc/settings.cluster.json ]; then
        cubectl node rsync --role=control /var/lib/terraform/
    fi
fi
popd >/dev/null 2>&1 || true
