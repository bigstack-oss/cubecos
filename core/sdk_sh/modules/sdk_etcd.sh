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

ETCD_TLS_SETTLE_TIMEOUT=${ETCD_TLS_SETTLE_TIMEOUT:-60}
ETCD_TLS_POLL=${ETCD_TLS_POLL:-2}

# etcdctl over https with the client certificate, whatever the node's mode
_etcd_tls_ctl()
{
    /usr/local/bin/etcdctl --command-timeout=5s --cacert=$ETCD_PKI_DIR/ca.crt \
        --cert=$ETCD_PKI_DIR/client.crt --key=$ETCD_PKI_DIR/client.key "$@"
}

# Wait until every member in $* (management IPs) answers https with the client certificate.
_etcd_tls_settled()
{
    local eps=$(printf 'https://%s:12379,' "$@") waited=0
    while : ; do
        [ "$(_etcd_tls_ctl --endpoints=${eps%,} endpoint health 2>/dev/null | grep -c 'is healthy')" = "$#" ] && return 0
        [ $waited -lt $ETCD_TLS_SETTLE_TIMEOUT ] || return 1
        sleep $ETCD_TLS_POLL
        waited=$((waited + ETCD_TLS_POLL))
    done
}

# Run a command on the control node at $1, locally when that is this node.
_etcd_tls_on()
{
    local addr=$1
    shift
    if ip -o addr show | grep -qF " $addr/" ; then
        "$@"
    else
        ( remote_run $addr "$*" ) </dev/null
    fi
}

# Move cube's etcd from compat to enforced TLS, one step at a time, stopping at the first
# that fails. A no-op once every member enforces. On HA it runs on the master control node,
# called when a roll completes (power_roll_advance): until then every node not rolled yet
# speaks plain http only. A single node runs it from its own migration boot (cubectl's
# cluster commit), and again at every later cluster commit until it gets past step 4.
# On HA it is not retried; run it again by hand once the cause is fixed.
#   1. every node holds the PKI (a node that could not pull it at its migration boot)
#   2. every member serves https next to http (cubectl this-node etcd-refresh, still compat)
#   3. every member answers https with the client certificate
#   4. every node drops the compat marker and restarts etcd-watch: clients move to https,
#      which every member in compat already serves
#   5. one member at a time moves its peer URL to https and restarts in enforce
# Until step 5 starts, a failure leaves the cluster serving http as before.
# Usage: $PROG etcd_tls_ladder
etcd_tls_ladder()
{
    is_control_node || return 0
    if [ ! -f $ETCD_PKI_DIR/ca.crt ] ; then
        log_info "etcd_tls_ladder: no etcd PKI, nothing to do"
        return 0
    fi

    source hex_tuning $SETTINGS_TXT cubesys.ha
    local ha=$T_cubesys_ha addrs addr
    if [ "$ha" = "true" ] ; then
        source hex_tuning $SETTINGS_TXT cubesys.control.addrs
        addrs=$(echo $T_cubesys_control_addrs | tr ',' ' ')
    else
        addrs=$(mgmt_ip)
    fi
    [ -n "$addrs" ] || { log_error "etcd_tls_ladder: no control node address" ; return 1 ; }

    if [ "$ha" = "true" ] ; then
        cubectl node rsync $ETCD_PKI_DIR ||
            { log_error "etcd_tls_ladder: cannot push $ETCD_PKI_DIR to every node" ; return 1 ; }
    fi

    for addr in $addrs ; do
        _etcd_tls_on $addr cubectl this-node etcd-refresh ||
            { log_error "etcd_tls_ladder: etcd on $addr does not serve https" ; return 1 ; }
    done
    if ! _etcd_tls_settled $addrs ; then
        log_error "etcd_tls_ladder: not every member answers https within ${ETCD_TLS_SETTLE_TIMEOUT}s"
        return 1
    fi

    local flip="[ ! -e $ETCD_TLS_COMPAT_MARK ] || { rm -f $ETCD_TLS_COMPAT_MARK && systemctl restart etcd-watch ; }"
    if [ "$ha" = "true" ] ; then
        cubectl node exec "$flip" ||
            { log_error "etcd_tls_ladder: cannot move every node's etcd clients to https" ; return 1 ; }
    else
        eval "$flip" || { log_error "etcd_tls_ladder: cannot move etcd clients to https" ; return 1 ; }
    fi
    log_info "etcd_tls_ladder: etcd clients use https"

    for addr in $addrs ; do
        _etcd_tls_on $addr cubectl this-node etcd-refresh ||
            { log_error "etcd_tls_ladder: etcd on $addr did not come back enforcing TLS" ; return 1 ; }
        if ! _etcd_tls_settled $addrs ; then
            log_error "etcd_tls_ladder: members not healthy within ${ETCD_TLS_SETTLE_TIMEOUT}s after $addr"
            return 1
        fi
    done
    log_info "etcd_tls_ladder: every member enforces etcd TLS"
}
