# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

pacemaker_remote_add()
{
    local node=$1

    if hex_sdk remote_run $node hex_sdk is_control_node ; then
        Quiet -n remote_run $node "timeout $SRVTO systemctl stop pacemaker || killall -9 pacemakerd"
        Quiet -n remote_run $node "timeout $SRVTO systemctl stop corosync || killall -9 corosync"
    fi
    Quiet -n remote_run $node "systemctl start pcsd"
    Quiet -n timeout $SRVSTO /usr/sbin/pcs host auth $node -u hacluster -p Cube0s!
    Quiet -n timeout $SRVSTO /usr/sbin/pcs cluster node add-remote $node
    if hex_sdk remote_run $node hex_sdk is_control_node ; then
        Quiet -n remote_run $node "systemctl reset-failed ; systemctl restart pacemaker corosync"
    fi
}

pacemaker_remote_remove()
{
    local node=$1

    Quiet -n timeout $SRVSTO /usr/sbin/pcs host auth $node -u hacluster -p Cube0s!
    Quiet -n timeout $SRVSTO /usr/sbin/pcs resource delete $node
    Quiet -n timeout $SRVSTO /usr/sbin/crm_node --force --remove $node
}

pacemaker_remote_cleanup()
{   
    Quiet -n timeout $SRVSTO /usr/sbin/pcs resource cleanup $(hostname)
}
