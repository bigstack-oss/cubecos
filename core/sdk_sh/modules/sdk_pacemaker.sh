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
        for i in 1 2 3 ; do
            if is_remote_running $node corosync ; then
                break
            else
                Quiet -n remote_run $node "systemctl restart corosync"
            fi
            sleep 15
        done

        for i in 1 2 3 ; do
            if is_remote_running $node pacemaker ; then
                break
            else
                Quiet -n remote_run $node "systemctl restart pacemaker"
            fi
            sleep 15
        done
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

pacemaker_cluster_stop()
{
    cubectl node exec -r control -pn "$HEX_SDK pacemaker_node_stop"
}

pacemaker_node_stop()
{
    timeout $SRVTO systemctl stop pcsd || killall -9 pcsd
    timeout $SRVTO systemctl stop pacemaker || killall -9 pacemakerd
    timeout $SRVTO systemctl stop corosync || killall -9 corosync
}

pacemaker_cluster_restart()
{
    cubectl node exec -r control -pn "$HEX_SDK pacemaker_node_restart"
}

pacemaker_node_restart()
{
    systemctl restart pcsd corosync pacemaker
    sleep 10
    is_running pcsd || systemctl restart pcsd
    is_running pacemaker || systemctl restart pacemaker
    is_running corosync || systemctl restart corosync
}
