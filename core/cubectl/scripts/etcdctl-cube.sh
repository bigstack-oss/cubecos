#!/bin/sh

# https with the client certificate once the node enforces etcd TLS: the PKI is in place and
# the rolling-upgrade compat marker is gone (cubectl util/etcdtls.go)
PKI=/etc/etcd-pki
if [ -f $PKI/ca.crt ] && [ ! -e /etc/appliance/state/etcd_tls_compat ] ; then
    /usr/local/bin/etcdctl --endpoints=https://127.0.0.1:12379 --cacert=$PKI/ca.crt --cert=$PKI/client.crt --key=$PKI/client.key "$@"
else
    /usr/local/bin/etcdctl --endpoints=127.0.0.1:12379 "$@"
fi
