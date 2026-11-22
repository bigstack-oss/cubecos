# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# remote nodes that have a resource in the CIB
pacemaker_remote_nodes()
{
    cibadmin -Q --xpath "//primitive[@provider='pacemaker'][@type='remote']" 2>/dev/null | grep -o '<primitive id="[^"]*"' | cut -d'"' -f2
}

pacemaker_remote_add()
{
    local node=$1
    local other out ctrl=0

    if hex_sdk remote_run $node hex_sdk is_control_node ; then
        ctrl=1
        Quiet -n remote_run $node "timeout $SRVTO systemctl stop pacemaker || killall -9 pacemakerd"
        Quiet -n remote_run $node "timeout $SRVTO systemctl stop corosync || killall -9 corosync"
    fi
    Quiet -n remote_run $node "systemctl start pcsd"
    Quiet -n timeout $SRVSTO /usr/sbin/pcs host auth $node -u hacluster -p Cube0s!
    # add-remote fails unless every remote node already in the CIB is in this
    # node's pcs known-hosts, which is empty after an upgrade
    for other in $(pacemaker_remote_nodes) ; do
        [ "x$other" = "x$node" ] || Quiet -n timeout $SRVSTO /usr/sbin/pcs host auth $other -u hacluster -p Cube0s!
    done
    out=$(timeout $SRVSTO /usr/sbin/pcs cluster node add-remote $node 2>&1)
    if [ $ctrl -eq 0 ] && ! pacemaker_remote_nodes | grep -qx "$node" ; then
        # no resource: a running pacemaker_remote would only block the next add
        log_error "pacemaker_remote_add: $node not added: $(echo $out)"
        echo "Error: pacemaker_remote_add: $node not added: $(echo $out)" >&2
        return 1
    fi
    Quiet -n remote_run $node "systemctl enable --now pacemaker_remote"
    Quiet -n pcs resource cleanup $node
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

pacemaker_node_stop()
{
    local node=${1:-$HOSTNAME}
    if [ "x$node" = "x$HOSTNAME" ] ; then
        timeout $SRVSTO systemctl stop pcsd || killall -9 pcsd
        timeout $SRVSTO systemctl stop pacemaker || killall -9 pacemakerd
        timeout $SRVSTO systemctl stop corosync || killall -9 corosync
    else
        remote_run $node "timeout $SRVSTO systemctl stop pcsd || killall -9 pcsd"
        remote_run $node "timeout $SRVSTO systemctl stop pacemaker || killall -9 pacemakerd"
        remote_run $node "timeout $SRVSTO systemctl stop corosync || killall -9 corosync"
    fi
}

pacemaker_cluster_stop()
{
    cmd -c "timeout $SRVSTO systemctl stop pcsd || killall -9 pcsd"
    cmd -c "timeout $SRVSTO systemctl stop pacemaker || killall -9 pacemakerd"
    cmd -c "timeout $SRVSTO systemctl stop corosync || killall -9 corosync"
}

pacemaker_node_restart()
{
    local node=${1:-$HOSTNAME}
    if [ "x$node" = "x$HOSTNAME" ] ; then
        systemctl restart pcsd corosync pacemaker
        sleep 10
        pacemaker_node_start
        sleep 10
        pcs resource cleanup
        pcs resource clear vip
    else
        remote_run $node "systemctl restart pcsd corosync pacemaker"
        sleep 10
        pacemaker_node_start $node
        sleep 10
        remote_run $node "pcs resource cleanup"
        remote_run $node  "pcs resource clear vip"
    fi
}

pacemaker_node_start()
{
    local node=${1:-$HOSTNAME}
    if [ "x$node" = "x$HOSTNAME" ] ; then
        is_running pcsd || systemctl restart pcsd
        is_running pacemaker || systemctl restart pacemaker
        is_running corosync || systemctl restart corosync
    else
        remote_run $node "$HEX_SDK is_running pcsd || systemctl restart pcsd"
        remote_run $node "$HEX_SDK is_running pacemaker || systemctl restart pacemaker"
        remote_run $node "$HEX_SDK is_running corosync || systemctl restart corosync"
    fi
}

pacemaker_cluster_restart()
{
    cmd -c "systemctl restart pcsd corosync pacemaker"
    sleep 10
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        pacemaker_node_start $node
    done
    sleep 10
    Quiet -n pcs resource cleanup
    Quiet -n pcs resource clear vip
}

# 0 only when pacemaker is settled (DC idle, nothing mid-transition) --
# distinguishes a genuine fault from a cluster still converging
pacemaker_settled()
{
    local dc state
    dc=$(crmadmin -D 2>/dev/null | awk '{print $NF}')
    [ -n "$dc" ] || return 1
    state=$(crmadmin -S "$dc" 2>/dev/null | grep -oE 'S_[A-Z_]+')
    [ "$state" = "S_IDLE" ] || return 1
    pcs status 2>/dev/null | grep -qiE 'Starting|Stopping|Promoting|Demoting|Pending' && return 1
    return 0
}

pacemaker()
{
    for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
        if [ "x$@" = "xstatus" ] ; then
            if remote_run $node "timeout $SRVTO pcs status" 2>/dev/null ; then
                break
            fi
        else
            if remote_run $node "timeout $SRVTO pcs status" >/dev/null 2>&1 ; then
                remote_run $node "timeout $SRVTO pcs $@"
                break
            fi
        fi
    done
}
