# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

KUBECTL=/usr/local/bin/kubectl
KP_BIN="/usr/bin/kapacitor"
ALERT_RESP_DIR="/var/alert_resp"
ALERT_EXTRA="/etc/kapacitor/alert_extra/configs.yml"

alert_vm_event_list()
{
    local cpu_crit=$(cat /etc/kapacitor/templates/tpl_alert_vm_cpu.tick | grep "crit(lambda" | awk -F' |)' '{print $9}')
    local cpu_warn=$(cat /etc/kapacitor/templates/tpl_alert_vm_cpu.tick | grep "warn(lambda" | awk -F' |)' '{print $14}')
    local mem_crit=$(cat /etc/kapacitor/templates/tpl_alert_vm_mem.tick | grep "crit(lambda" | awk -F' |)' '{print $9}')
    local mem_warn=$(cat /etc/kapacitor/templates/tpl_alert_vm_mem.tick | grep "warn(lambda" | awk -F' |)' '{print $14}')

    if [ -n "$VERBOSE" ]; then
        echo "CPU00006C (VM cpu usage exceeds $cpu_crit%)"
        echo "CPU00005W (VM cpu usage exceeds $cpu_warn%)"
        echo "MEM00006C (VM memory usage exceeds $mem_crit%)"
        echo "MEM00005W (VM memory usage exceeds $mem_warn%)"
    else
        echo "CPU00006C"
        echo "CPU00005W"
        echo "MEM00006C"
        echo "MEM00005W"
    fi
}

alert_resp_jail_enter()
{
    $KUBECTL exec -i --tty resp-runner -- bash
}

alert_resp_jail_restart()
{
    if $KUBECTL get all | grep -q pod/resp-runner; then
        $KUBECTL delete pod resp-runner
    fi

    $KUBECTL run resp-runner --image=localhost:5080/bigstack/shell
}

alert_resp_jail_start()
{
    if ! $KUBECTL get all | grep -q pod/resp-runner; then
        $KUBECTL run resp-runner --image=localhost:5080/bigstack/shell
    fi
}

alert_jail_run()
{
    local fname=$1
    local ext="${fname##*.}"
    local alert_data=$2

    $KUBECTL cp $fname resp-runner:$fname
    if [ "$ext" == "shell" ]; then
        echo  $alert_data | $KUBECTL exec -i resp-runner -- bash $fname
    elif [ "$ext" == "bin" ]; then
        echo  $alert_data | $KUBECTL exec -i resp-runner -- $fname
    fi
}

alert_resp_runner()
{
    # check if stdin is empty
    if test -t 0; then
        return 0
    fi

    # redirect STDIN data to $alert_data
    local alert_data=$(cat | jq -c .data.series[0] 2>/dev/null)
    if [ -z "$alert_data" ]; then
        return 0
    fi

    local name=$1
    local type=${2:-shell}
    local fname=$ALERT_RESP_DIR/exec_$name.$type

    alert_jail_run $fname "$alert_data"
}

# Usage: $PROG alert_disable_project_by_id $project_id
alert_disable_project_by_id()
{
    local TENANT_ID=$1
    $KP_BIN delete tasks *_$TENANT_ID
}

# Usage: $PROG alert_enable_project_by_id $project_id
alert_enable_project_by_id()
{
    local TENANT_ID=$1
    local VARS=/tmp/proj_vars.json

    echo "{ \"where_filter\": {\"type\": \"lambda\", \"value\": \"\\\"tenant_id\\\" == '$TENANT_ID'\"} }" > $VARS

    $KP_BIN define-template tpl_alert_vm_cpu -tick /etc/kapacitor/templates/tpl_alert_vm_cpu.tick
    $KP_BIN define alert_vm_cpu_$TENANT_ID -template tpl_alert_vm_cpu -vars $VARS
    $KP_BIN enable alert_vm_cpu_$TENANT_ID
    $KP_BIN define-template tpl_alert_vm_mem -tick /etc/kapacitor/templates/tpl_alert_vm_mem.tick
    $KP_BIN define alert_vm_mem_$TENANT_ID -template tpl_alert_vm_mem -vars $VARS
    $KP_BIN enable alert_vm_mem_$TENANT_ID
}

# Usage: $PROG alert_disable_project_by_name $project_name
alert_disable_project_by_name()
{
    local TENANT=$1
    local TENANT_ID=$(os_get_project_id_by_name $TENANT)
    alert_disable_project_by_id $TENANT_ID
}

# Usage: $PROG alert_enable_project_by_name $project_name
alert_enable_project_by_name()
{
    local TENANT=$1
    local TENANT_ID=$(os_get_project_id_by_name $TENANT)
    alert_enable_project_by_id $TENANT_ID
}

alert_sync_tenant()
{
    if [ ! -f /run/cube_commit_done  ]; then
        return 0
    fi

    local ENABLED_TENANT_LIST=$($KP_BIN list tasks | grep vm_cpu | awk '{print $1}' | awk -F'_' '{print $4}' | tr '\n' ',')

    readarray tid_array <<<"$(openstack project list -c ID -f value)"
    declare -p tid_array > /dev/null
    for tid in "${tid_array[@]}"
    do
        if $(echo $ENABLED_TENANT_LIST | grep -q $tid); then
            :
        else
            alert_enable_project_by_id $tid
        fi
    done
}

alert_cluster_sync_tenant()
{
    cubectl node exec -r control -p /usr/sbin/hex_sdk alert_sync_tenant
}

alert_unsync_tenant()
{
    local ENABLED_TENANT_LIST=$(openstack project list -c ID -f value | tr '\n' ',')

    readarray tid_array <<<"$($KP_BIN list tasks | grep vm_cpu | awk '{print $1}' | awk -F'_' '{print $4}')"
    declare -p tid_array > /dev/null
    for tid in "${tid_array[@]}"
    do
        if $(echo $ENABLED_TENANT_LIST | grep -q $tid); then
            :
        else
            alert_disable_project_by_id $tid
        fi
    done
}

alert_cluster_unsync_tenant()
{
    cubectl node exec -r control -p /usr/sbin/hex_sdk alert_unsync_tenant
}


alert_extra_update()
{
    local msgPrefix=$1
    cubectl node exec -r control -p "echo \"msgPrefix: $msgPrefix\" > $ALERT_EXTRA" >/dev/null
    cubectl node exec -r control -p kapacitor define alert_events -tick /etc/kapacitor/tasks/alert_events.tick >/dev/null
}
