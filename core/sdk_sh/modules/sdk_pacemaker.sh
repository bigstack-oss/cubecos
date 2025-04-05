# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

pacemaker_remote_add()
{
    local node=$1
    local timeout=${2:-480}

    # wait for remote pcsd started by remote node
    # check "hex_config -d" for startup order cluster -> pacemaker
    local i=0
    while [ $i -lt $timeout ]; do
        if echo "" | nc $node 2224 2>/dev/null; then
            /usr/sbin/pcs host auth $node -u hacluster -p Cube0s!
            /usr/sbin/pcs cluster node add-remote $node
            break
        else
            sleep 1
        fi
        i=$(expr $i + 1)
    done
    [ $i -lt $timeout ]
}

pacemaker_remote_remove()
{
    local node=$1
    /usr/sbin/pcs host auth $node -u hacluster -p Cube0s!
    /usr/sbin/pcs resource delete $node
    /usr/sbin/crm_node --force --remove $node
}

pacemaker_remote_cleanup()
{
    /usr/sbin/pcs resource cleanup $(hostname) 2>/dev/null
}
