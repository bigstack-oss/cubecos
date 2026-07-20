# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

is_running()
{
    systemctl show -p SubState $1 | grep -q running
}

# True when $1 is this node; lets is_remote_* skip ssh-to-self.
is_local_node()
{
    [ "$1" = "$HOSTNAME" ] || [ "$1" = "$(hostname -s)" ] || [ "$1" = "localhost" ] || [ "$1" = "127.0.0.1" ]
}

is_remote_running()
{
    if is_local_node "$1" ; then
        is_running $2
    else
        ssh root@$1 $HEX_SDK is_running $2 >/dev/null 2>&1
    fi
}

is_active()
{
    systemctl show -p SubState $1 | grep -q active
}

is_remote_active()
{
    if is_local_node "$1" ; then
        is_active $2
    else
        ssh root@$1 $HEX_SDK is_active $2 >/dev/null 2>&1
    fi
}

is_centos()
{
    grep -q "CentOS Linux" /etc/system-release
}

is_rhel()
{
    grep -q "Red Hat Enterprise Linux" /etc/system-release
}

# source hex_tuning $SETTINGS_TXT doesn't work in a cron job, we use
# T_cubesys_role=$(awk '/role:/{print $2}' /etc/policies/cubesys/cubesys1_0.yml | tr -d '\n')

is_undef_node()
{
    T_cubesys_role=$(awk '/role:/{print $2}' /etc/policies/cubesys/cubesys1_0.yml | tr -d '\n')
    [ "$T_cubesys_role" == "undef" ]
}

is_control_node()
{
    T_cubesys_role=$(awk '/role:/{print $2}' /etc/policies/cubesys/cubesys1_0.yml | tr -d '\n')
    [ "$T_cubesys_role" == "control" ] || [ "$T_cubesys_role" == "control-network" ] || [ "$T_cubesys_role" == "control-converged" ] || [ "$T_cubesys_role" == "edge-core" ] || [ "$T_cubesys_role" == "moderator" ]
}

is_compute_node()
{
    T_cubesys_role=$(awk '/role:/{print $2}' /etc/policies/cubesys/cubesys1_0.yml | tr -d '\n')
    [ "$T_cubesys_role" == "compute" ] || [ "$T_cubesys_role" == "control-converged" ] || [ "$T_cubesys_role" == "edge-core" ]
}

is_pure_compute_node()
{
    T_cubesys_role=$(awk '/role:/{print $2}' /etc/policies/cubesys/cubesys1_0.yml | tr -d '\n')
    [ "$T_cubesys_role" == "compute" ]
}

is_storage_node()
{
    T_cubesys_role=$(awk '/role:/{print $2}' /etc/policies/cubesys/cubesys1_0.yml | tr -d '\n')
    [ "$T_cubesys_role" == "storage" ] || [ "$T_cubesys_role" == "control-converged" ] || [ "$T_cubesys_role" == "edge-core" ]
}

is_edge_node()
{
    T_cubesys_role=$(awk '/role:/{print $2}' /etc/policies/cubesys/cubesys1_0.yml | tr -d '\n')
    [ "$T_cubesys_role" == "edge-core" ] || [ "$T_cubesys_role" == "moderator" ]
}

is_core_node()
{
    T_cubesys_role=$(awk '/role:/{print $2}' /etc/policies/cubesys/cubesys1_0.yml | tr -d '\n')
    [ "$T_cubesys_role" == "edge-core" ]
}

is_moderator_node()
{
    T_cubesys_role=$(awk '/role:/{print $2}' /etc/policies/cubesys/cubesys1_0.yml | tr -d '\n')
    [ "$T_cubesys_role" == "moderator" ]
}

is_first_three_compute_node()
{
    if cubectl node list -r compute -j | jq -r .[].hostname | head -3 | grep -q $(hostname); then
        return 0
    else
        return 1
    fi
}

is_node_repairing()
{
    if [ -e /run/cube_cluster_repairing ]; then
        if [ "$VERBOSE" = "1" ]; then
            local cmd=$(echo $(basename $(readlink /run/cube_cluster_repairing) 2>/dev/null))
            local pid=$(cat /run/cube_cluster_repairing 2>/dev/null)
            local eps=$(ps --no-headers -o etime ${pid:-0} 2>/dev/null | xargs)
            echo -n "${cmd},${pid},${eps}"
        fi
        hex_sdk stale_repair_clear # Do not replace hex_sdk with $HEX_SDK which cmd does not expand
        return 0
    else
        return 1
    fi
}

is_repairing()
{
    [ "$VERBOSE" = "1" ] || local reg_flg="-q"
    if timeout 5 $HEX_SDK cmd -cv is_node_repairing $@ | grep $reg_flg "|0|" ; then
        return 0
    else
        return 1
    fi
}

is_node_checking()
{
    local cmd=$1
    [ "x$cmd" != "x" ] || Error "missing cmd"
    local checking=false

    if [ -e /run/${cmd}ing ]; then
        if [ "$VERBOSE" = "1" ]; then
            local pid=$(cat /run/${cmd}ing 2>/dev/null)
            local eps=$(ps --no-headers -o etime ${pid:-0} 2>/dev/null | xargs)
            echo -n "${cmd},${pid},${eps}"
        fi
        return 0
    else
        return 1
    fi
}

is_checking()
{
    [ "$VERBOSE" = "1" ] || local reg_flg="-q"
    if cmd -cv is_node_checking $@ | grep $reg_flg "|0|" ; then
        return 0
    else
        return 1
    fi
}

is_sshable()
{
    local node=${1:-$HOSTNAME}
    local mf_ssh=/run/${FUNCNAME[0]}_${node}
    local ret=1

    if [ -e $mf_ssh ] && [ $(find $mf_ssh -type f -mmin -1 2>/dev/null | wc -l) -eq 1 ] ; then
        ret=0
    else
        rm -f $mf_ssh
        local mf_tmp=$(mktemp -u /tmp/is_sshable.XXXX)
        ( timeout 2 ssh -o LogLevel=quiet root@$node exit && rm -f $mf_tmp ) &
        local pid=$!
        echo $pid > $mf_tmp
        for i in 1 2 3 ; do
            if [ -e $mf_tmp ] ; then
                sleep 1
            else
                ret=0
                touch $mf_ssh
                break
            fi
        done
        if ps -p $pid >/dev/null 2>&1 ; then
            kill $pid
        fi
        rm -f $mf_tmp
    fi

    return $ret
}

# Cluster-wide "a roll is in progress" marker. On cephfs so every node sees the
# same answer and it survives an A/B partition switch. Set/cleared by the roll
# brackets (ceph_enter_rolling/ceph_leave_rolling for upgrades, power_roll for
# restarts) -- defined here in modules.pre so any module can call it.
CLUSTER_ROLLING_MARKER=${CLUSTER_ROLLING_MARKER:-/mnt/cephfs/.cluster_rolling}
# Ignore a marker older than this: a roll that died without clearing it must not
# disable auto-repair forever.
CLUSTER_ROLLING_MARKER_TTL=${CLUSTER_ROLLING_MARKER_TTL:-21600}   # 6h

cluster_rolling_marker_set()
{
    mountpoint -q /mnt/cephfs 2>/dev/null || return 0
    date +%s > $CLUSTER_ROLLING_MARKER 2>/dev/null
    return 0
}

cluster_rolling_marker_clear()
{
    rm -f $CLUSTER_ROLLING_MARKER 2>/dev/null
    return 0
}

cluster_rolling_marker_active()
{
    [ -f "$CLUSTER_ROLLING_MARKER" ] || return 1
    local age=$(( $(date +%s) - $(stat -c %Y "$CLUSTER_ROLLING_MARKER" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$CLUSTER_ROLLING_MARKER_TTL" ]
}

is_node_rolling_upgrade()
{
    local ret=1
    # Explicit marker: covers the whole roll, including the first node's drain --
    # before any node has rebooted there is no firmware skew and the log says
    # "evacuating", so neither heuristic below fires yet.
    if cluster_rolling_marker_active ; then
        ret=0
    fi
    if cmd -v "cat /run/cube_bootstrap.log" | grep -q -e 'Rebooting' -e 'rolling upgrade' ; then
        $HEX_SDK cube_cluster_ready || ret=0
    fi
    if [ $(cmd -v "hex_cli -c firmware list | grep -i active" | cut -d"|" -f3 | cut -d" " -f2 | sort -u | sed "/^$/d" | wc -l) -gt 1 ] ; then
        ret=0
    fi

    return $ret
}

is_vip_active()
{
    local ret=0
    for i in {1..5} ; do
        if cmd -cv "pcs resource status vip 2>/dev/null" | cut -d"|" -f3 | sort -u | sort -u | grep -q "vip.*Started" ; then
            sleep 1
        else
            ret=1 && break
        fi
    done

    return $ret
}

is_vip_reachable()
{
    local ret=0
    local vip=$(shared_ip)

    ping -q -c 10 ${vip:-256.256.256.256} >/dev/null 2>&1 || ret=1

    return $ret
}

is_valid_json()
{
    echo "${1}" | _hex_function_ret jq "."
    return $?
}
