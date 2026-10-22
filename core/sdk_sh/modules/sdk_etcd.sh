# CUBE SDK
# cube's etcd (client 12379, peer 12380): TLS during and after an upgrade

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# Put this node in etcd TLS compat when the release it upgrades from did not enforce TLS:
# clients stay on http, and members serve http next to https, until etcd_tls_ladder runs at
# the end of the roll. That is the case when the previous root has no PKI, still carried
# the compat marker (a roll whose ladder never completed), or ran a config without client
# certificate checks. A compute node has no etcd config, so the PKI decides for it.
# /etc/appliance/state is not carried across the A/B switch, hence the look at the previous
# root rather than at this one.
# Usage: $PROG etcd_tls_migrate_prepare <previous root>
etcd_tls_migrate_prepare()
{
    local prev=${1:-}
    local conf=$prev/etc/etcd/etcd.conf.yml

    if [ ! -f $prev$ETCD_PKI_DIR/ca.crt ] || [ -e $prev$ETCD_TLS_COMPAT_MARK ] ||
       { [ -f $conf ] && ! grep -q 'client-cert-auth: true' $conf ; } ; then
        mkdir -p $(dirname $ETCD_TLS_COMPAT_MARK)
        touch $ETCD_TLS_COMPAT_MARK
    fi
}
