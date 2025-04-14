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
    stale_repair_clear
    local fixing=false
    if [ -e $CLUSTER_REPAIRING ]; then
        fixing=true
    fi
    if [ "$VERBOSE" = "1" ]; then
        local srv=$(echo $(basename $(readlink $CLUSTER_REPAIRING) 2>/dev/null) | sed -e "s/^health_//" -e "s/_repair$//")
        local pid=$(cat $CLUSTER_REPAIRING 2>/dev/null)
        local eps=$(ps --no-headers -o etime ${pid:-NOPID} 2>/dev/null | xargs)
        printf "{ \"node\" : \"$HOSTNAME\",\"fixing\" : \"$fixing\",\"service\" : \"$srv\",\"pid\" : \"$pid\",\"elaps\" : \"$eps\" }"
    fi
    if [ "$fixing" = "false" ]; then
        return 1
    else
        return 0
    fi
}

is_repairing()
{
    for node in $(cubectl node exec -pn "$HEX_SDK is_node_repairing >/dev/null && echo \$HOSTNAME"); do
        remote_run $node "$HEX_SDK ${VERBOSE:+-v} is_node_repairing" 2>/dev/null
        return 0
    done

    return 1
}
