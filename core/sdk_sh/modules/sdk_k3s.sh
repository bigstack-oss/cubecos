# HEX SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

k3s_take_leader()
{
    source hex_tuning $SETTINGS_TXT cubesys.control.addrs
    if [ -z "$T_cubesys_control_addrs" ] ; then
        exit 0
    fi

    local eps=$(sed -e 's/,/:2379&/g' -e 's/$/:2379&/g' <<< $T_cubesys_control_addrs)

    export ETCDCTL_CACERT='/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt'
    export ETCDCTL_CERT='/var/lib/rancher/k3s/server/tls/etcd/server-client.crt' 
    export ETCDCTL_KEY='/var/lib/rancher/k3s/server/tls/etcd/server-client.key'

    local member_id=$(etcdctl endpoint status -w json | jq '.[].Status.header.member_id' | xargs printf '%x')
    Quiet -n etcdctl --endpoints=$eps move-leader $member_id
}

k3s_reconfigure_mtu()
{
    # Delete dev flannel.1 and restart k3s 
    # so that flannel.1 can be recreated to honor new MTU
    Quiet -n ip link delete flannel.1
    Quiet -n systemctl restart k3s

    # Restart all pods on current node so that new pods will honor new MTU
    Quiet -n k3s kubectl delete pods -A --field-selector spec.nodeName=$HOSTNAME --force
}
