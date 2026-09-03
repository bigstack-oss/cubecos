# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

haproxy_stats()
{
    echo "show stat" | nc -U $1 | cut -d "," -f 1,2,37  | column -s, -t | grep -v "BACKEND\|FRONTEND"
}

# The VIP-fronting instance carries the control-plane API traffic; the per-node
# instance keeps its own socket. Both are "level admin", so the runtime API can
# drain and restore servers.
haproxy_ha_sock()
{
    local sock=/run/haproxy/admin.sock
    [ -S $sock ] && echo $sock
}

# one line per server: pxname svname status check_status. Field 18 is the state
# (UP/DOWN/MAINT); field 37 is only the last check's verdict.
haproxy_server_states()
{
    echo "show stat" | nc -U $1 2>/dev/null | \
        awk -F, 'NR>1 && $1 !~ /^#/ && $2 != "BACKEND" && $2 != "FRONTEND" && $2 != "" {print $1, $2, $18, $37}'
}

# $1 socket, $2 enable|disable, $3 pxname/svname
haproxy_server_admin()
{
    echo "$2 server $3" | nc -U $1 >/dev/null 2>&1
}
