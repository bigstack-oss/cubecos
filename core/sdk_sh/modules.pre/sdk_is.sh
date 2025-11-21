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

is_remote_running()
{
    ssh root@$1 $HEX_SDK is_running $2 >/dev/null 2>&1
}

is_active()
{
    systemctl show -p SubState $1 | grep -q active
}

is_remote_active()
{
    ssh root@$1 $HEX_SDK is_active $2 >/dev/null 2>&1
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
    if cmd -cv is_node_repairing $@ | grep $reg_flg "|0|" ; then
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

    if [ -e $mf_ssh ] && [ $(find $mf_ssh -type f -mmin -1 | wc -l) -eq 1 ] ; then
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

is_node_rolling_upgrade()
{
    local ret=1
    if cmd -v "cat /run/cube_bootstrap.log" | grep -q -e 'Rebooting' -e 'Starting auto rolling upgrade' ; then
        $HEX_SDK cube_cluster_ready || ret=0
    fi
    if [ $(cmd -v "hex_cli -c firmware list | grep -i active" | cut -d"|" -f3 | sort -u | sed "/^$/d" | wc -l) -gt 1 ] ; then
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
