# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

alert_vm_event_list()
{
    local cpu_crit=$(cat /etc/kapacitor/templates/tpl_alert_vm_cpu.tick | grep "crit(lambda" | awk -F' |)' '{print $9}')
    local cpu_warn=$(cat /etc/kapacitor/templates/tpl_alert_vm_cpu.tick | grep "warn(lambda" | awk -F' |)' '{print $14}')
    local mem_crit=$(cat /etc/kapacitor/templates/tpl_alert_vm_mem.tick | grep "crit(lambda" | awk -F' |)' '{print $9}')
    local mem_warn=$(cat /etc/kapacitor/templates/tpl_alert_vm_mem.tick | grep "warn(lambda" | awk -F' |)' '{print $14}')

    if [ -n "$VERBOSE" ] ; then
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
    if $KUBECTL get all | grep -q pod/resp-runner ; then
        $KUBECTL delete pod resp-runner
    fi

    $KUBECTL run resp-runner --image=localhost:5080/bigstack/shell
}

alert_resp_jail_start()
{
    if ! $KUBECTL get all | grep -q pod/resp-runner ; then
        $KUBECTL run resp-runner --image=localhost:5080/bigstack/shell
    fi
}

alert_jail_run()
{
    local fname=$1
    local ext="${fname##*.}"
    local alert_data=$2

    $KUBECTL cp $fname resp-runner:$fname
    if [ "$ext" == "shell" ] ; then
        echo  $alert_data | $KUBECTL exec -i resp-runner -- bash $fname
    elif [ "$ext" == "bin" ] ; then
        echo  $alert_data | $KUBECTL exec -i resp-runner -- $fname
    fi
}

alert_resp_runner()
{
    # check if stdin is empty
    if test -t 0 ; then
        return 0
    fi

    # redirect STDIN data to $alert_data
    local alert_data=$(cat | jq -c .data.series[0] 2>/dev/null)
    if [ -z "$alert_data" ] ; then
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
    local tenant_id=$1
    $KP_BIN delete tasks *_$tenant_id
}

# Usage: $PROG alert_enable_project_by_id $project_id
alert_enable_project_by_id()
{
    local tenant_id=$1
    local VARS=/tmp/proj_vars.json

    echo "{ \"where_filter\": {\"type\": \"lambda\", \"value\": \"\\\"tenant_id\\\" == '$tenant_id'\"} }" > $VARS

    $KP_BIN define-template tpl_alert_vm_cpu -tick /etc/kapacitor/templates/tpl_alert_vm_cpu.tick
    $KP_BIN define alert_vm_cpu_$tenant_id -template tpl_alert_vm_cpu -vars $VARS
    $KP_BIN enable alert_vm_cpu_$tenant_id
    $KP_BIN define-template tpl_alert_vm_mem -tick /etc/kapacitor/templates/tpl_alert_vm_mem.tick
    $KP_BIN define alert_vm_mem_$tenant_id -template tpl_alert_vm_mem -vars $VARS
    $KP_BIN enable alert_vm_mem_$tenant_id
}

# Usage: $PROG alert_disable_project_by_name $project_name
alert_disable_project_by_name()
{
    local tenant=$1
    local tenant_id=$($HEX_SDK os_get_project_id_by_name $tenant)
    alert_disable_project_by_id $tenant_id
}

# Usage: $PROG alert_enable_project_by_name $project_name
alert_enable_project_by_name()
{
    local tenant=$1
    local tenant_id=$($HEX_SDK os_get_project_id_by_name $tenant)
    alert_enable_project_by_id $tenant_id
}

alert_sync_tenant()
{
    if [ ! -f /run/cube_commit_done  ] ; then
        return 0
    fi

    local enabled_tenant_list=$($KP_BIN list tasks | grep vm_cpu | awk '{print $1}' | awk -F'_' '{print $4}' | tr '\n' ',')

    readarray tid_array <<<"$(openstack project list -c ID -f value)"
    declare -p tid_array > /dev/null
    for tid in "${tid_array[@]}" ; do
        if $(echo $enabled_tenant_list | grep -q $tid) ; then
            :
        else
            alert_enable_project_by_id $tid
        fi
    done
}

alert_cluster_sync_tenant()
{
    cubectl node exec -r control -p $HEX_SDK alert_sync_tenant
}

alert_unsync_tenant()
{
    local enabled_tenant_list=$(openstack project list -c ID -f value | tr '\n' ',')

    readarray tid_array <<<"$($KP_BIN list tasks | grep vm_cpu | awk '{print $1}' | awk -F'_' '{print $4}')"
    declare -p tid_array > /dev/null
    for tid in "${tid_array[@]}" ; do
        if $(echo $enabled_tenant_list | grep -q $tid) ; then
            :
        else
            alert_disable_project_by_id $tid
        fi
    done
}

alert_cluster_unsync_tenant()
{
    cubectl node exec -r control -p $HEX_SDK alert_unsync_tenant
}

alert_extra_update()
{
    local msgPrefix=$1
    cubectl node exec -r control -p "echo \"msgPrefix: $msgPrefix\" > $ALERT_EXTRA" >/dev/null
    cubectl node exec -r control -p kapacitor define alert_events -tick /etc/kapacitor/tasks/alert_events.tick >/dev/null
}

alert_get_setting()
{
    # output format: {
    #   titlePrefix: "",
    #   sender: {
    #     email: {
    #       host: "",
    #       port: "",
    #       username: "",
    #       password: "",
    #       from: ""
    #     }
    #   },
    #   receiver: {
    #     emails: [
    #       {
    #         address: "",
    #         note: ""
    #       }
    #     ],
    #     slacks: [
    #       {
    #         url: "",
    #         username: "",
    #         description: "",
    #         workspace: "",
    #         channel: ""
    #       }
    #     ]
    #   }
    # }

    # load the tunings into the env
    # title prefix
    source hex_tuning $SETTINGS_TXT kapacitor.alert.setting.titlePrefix
    # sender email
    source hex_tuning $SETTINGS_TXT kapacitor.alert.setting.sender.email.host
    source hex_tuning $SETTINGS_TXT kapacitor.alert.setting.sender.email.port
    source hex_tuning $SETTINGS_TXT kapacitor.alert.setting.sender.email.username
    source hex_tuning $SETTINGS_TXT kapacitor.alert.setting.sender.email.password
    source hex_tuning $SETTINGS_TXT kapacitor.alert.setting.sender.email.from
    # receiver email
    local receiver_email_count_minus_one=$(($(grep -E "kapacitor.alert.setting.receiver.emails.[0-9]+.address" $SETTINGS_TXT | wc -l) - 1))
    for i in $(seq 0 "$receiver_email_count_minus_one") ; do
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.setting.receiver.emails.$i.address"
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.setting.receiver.emails.$i.note"
    done
    # receiver slack
    local receiver_slack_count_minus_one=$(($(grep -E "kapacitor.alert.setting.receiver.slacks.[0-9]+.url" $SETTINGS_TXT | wc -l) - 1))
    for i in $(seq 0 "$receiver_slack_count_minus_one") ; do
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.setting.receiver.slacks.$i.url"
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.setting.receiver.slacks.$i.username"
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.setting.receiver.slacks.$i.description"
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.setting.receiver.slacks.$i.workspace"
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.setting.receiver.slacks.$i.channel"
    done
    # receiver exec shell
    local receiver_exec_shell_count_minus_one=$(($(grep -E "kapacitor.alert.setting.receiver.execs.shells.[0-9]+.name" $SETTINGS_TXT | wc -l) - 1))
    for i in $(seq 0 "$receiver_exec_shell_count_minus_one") ; do
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.setting.receiver.execs.shells.$i.name"
    done
    # receiver exec bin
    local receiver_exec_bin_count_minus_one=$(($(grep -E "kapacitor.alert.setting.receiver.execs.bins.[0-9]+.name" $SETTINGS_TXT | wc -l) - 1))
    for i in $(seq 0 "$receiver_exec_bin_count_minus_one") ; do
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.setting.receiver.execs.bins.$i.name"
    done

    # format the JSON string
    # title prefix
    local title_prefix=$T_kapacitor_alert_setting_titlePrefix
    # sender email
    local se=$(jq -c -n \
        --arg host "$T_kapacitor_alert_setting_sender_email_host" \
        --arg port "$T_kapacitor_alert_setting_sender_email_port" \
        --arg username "$T_kapacitor_alert_setting_sender_email_username" \
        --arg password "$T_kapacitor_alert_setting_sender_email_password" \
        --arg from "$T_kapacitor_alert_setting_sender_email_from" \
        '{host: $host, port: $port, username: $username, password: $password, from: $from}')
    # receiver email
    local re_count=0
    local re="["
    for i in $(seq 0 "$receiver_email_count_minus_one") ; do
        local address_key="T_kapacitor_alert_setting_receiver_emails_${i}_address"
        local note_key="T_kapacitor_alert_setting_receiver_emails_${i}_note"

        if [[ "${!address_key}" == "" ]] ; then
            continue
        fi

        if [[ "$re_count" -gt 0 ]] ; then
            re+=","
        fi

        ((re_count++))
        re+=$(jq -c -n \
            --arg address "${!address_key}" \
            --arg note "${!note_key}" \
            '{address: $address, note: $note}')
    done
    re+="]"
    # receiver slack
    local rs_count=0
    local rs="["
    for i in $(seq 0 "$receiver_slack_count_minus_one") ; do
        local url_key="T_kapacitor_alert_setting_receiver_slacks_${i}_url"
        local username_key="T_kapacitor_alert_setting_receiver_slacks_${i}_username"
        local description_key="T_kapacitor_alert_setting_receiver_slacks_${i}_description"
        local workspace_key="T_kapacitor_alert_setting_receiver_slacks_${i}_workspace"
        local channel_key="T_kapacitor_alert_setting_receiver_slacks_${i}_channel"

        if [[ "${!url_key}" == "" ]] ; then
            continue
        fi

        if [[ "$rs_count" -gt 0 ]] ; then
            rs+=","
        fi

        ((rs_count++))
        rs+=$(jq -c -n \
            --arg url "${!url_key}" \
            --arg username "${!username_key}" \
            --arg description "${!description_key}" \
            --arg workspace "${!workspace_key}" \
            --arg channel "${!channel_key}" \
            '{url: $url, username: $username, description: $description, workspace: $workspace, channel: $channel}')
    done
    rs+="]"
    # receiver exec shell
    local res_count=0
    local res="["
    for i in $(seq 0 "$receiver_exec_shell_count_minus_one") ; do
        local name_key="T_kapacitor_alert_setting_receiver_execs_shells_${i}_name"

        if [[ "${!name_key}" == "" ]] ; then
            continue
        fi

        if [[ "$res_count" -gt 0 ]] ; then
            res+=","
        fi

        ((res_count++))
        res+=$(jq -c -n \
            --arg name "${!name_key}" \
            '{name: $name}')
    done
    res+="]"
    # receiver exec bin
    local reb_count=0
    local reb="["
    for i in $(seq 0 "$receiver_exec_bin_count_minus_one") ; do
        local name_key="T_kapacitor_alert_setting_receiver_execs_bins_${i}_name"

        if [[ "${!name_key}" == "" ]] ; then
            continue
        fi

        if [[ "$reb_count" -gt 0 ]] ; then
            reb+=","
        fi

        ((reb_count++))
        reb+=$(jq -c -n \
            --arg name "${!name_key}" \
            '{name: $name}')
    done
    reb+="]"

    # output
    jq -c -n \
        --arg titlePrefix "$title_prefix" \
        --argjson senderEmail "$se" \
        --argjson receiverEmail "$re" \
        --argjson receiverSlack "$rs" \
        --argjson receiverExecShell "$res" \
        --argjson receiverExecBin "$reb" \
        '{titlePrefix: $titlePrefix, sender: {email: $senderEmail}, receiver: {emails: $receiverEmail, slacks: $receiverSlack, execs: {shells: $receiverExecShell, bins: $receiverExecBin}}}'
}

alert_set_setting_title_prefix()
{
    # input format: {
    #   titlePrefix: "",
    # }

    # process inputs
    local input=${1:-""}
    local title_prefix=$(echo $input | jq -r '.titlePrefix')

    # prepare the environment
    local input_dir=$(MakeTempDir)

    # prepare the policy file
    mkdir -p "$input_dir/alert_setting"
    cp -f "/etc/policies/alert_setting/alert_setting1_0.yml" "$input_dir/alert_setting/"
    local policy_file="$input_dir/alert_setting/alert_setting1_0.yml"
    yq -i ".titlePrefix = \"$title_prefix\"" $policy_file

    # apply the changes
    $HEX_CFG apply $input_dir
    local ret=$?
    RemoveTempFiles
    return $ret
}

alert_set_setting_sender_email()
{
    # input format: {
    #   host: "",
    #   port: "",
    #   username: "",
    #   password: "",
    #   from: "",
    # }

    # process inputs
    local input=${1:-""}
    local host=$(echo $input | jq -r '.host')
    local port=$(echo $input | jq -r '.port')
    local username=$(echo $input | jq -r '.username')
    local password=$(echo $input | jq -r '.password')
    local from=$(echo $input | jq -r '.from')

    # prepare the environment
    local input_dir=$(MakeTempDir)

    # prepare the policy file
    mkdir -p "$input_dir/alert_setting"
    cp -f "/etc/policies/alert_setting/alert_setting1_0.yml" "$input_dir/alert_setting/"
    local policy_file="$input_dir/alert_setting/alert_setting1_0.yml"
    yq -i ".sender.email.host = \"$host\"" $policy_file
    yq -i ".sender.email.port = \"$port\"" $policy_file
    yq -i ".sender.email.username = \"$username\"" $policy_file
    yq -i ".sender.email.password = \"$password\"" $policy_file
    yq -i ".sender.email.from = \"$from\"" $policy_file

    # apply the changes
    $HEX_CFG apply $input_dir
    local ret=$?
    RemoveTempFiles
    return $ret
}

alert_put_setting_receiver_email()
{
    # input format: {
    #   address: "",
    #   note: "",
    # }

    # process inputs
    local input=${1:-""}
    local address=$(echo $input | jq -r '.address')
    local note=$(echo $input | jq -r '.note')

    # prepare the environment
    local input_dir=$(MakeTempDir)

    # prepare the policy file
    mkdir -p "$input_dir/alert_setting"
    cp -f "/etc/policies/alert_setting/alert_setting1_0.yml" "$input_dir/alert_setting/"
    local policy_file="$input_dir/alert_setting/alert_setting1_0.yml"
    local receiver_email_count_minus_one=$(($(yq '.receiver.emails | length' $policy_file) - 1))
    local is_update="false"
    # update
    for i in $(seq 0 "$receiver_email_count_minus_one") ; do
        if [[ "$address" == "$(yq ".receiver.emails[$i].address" $policy_file)" ]] ; then
            yq -i ".receiver.emails[$i].address = \"$address\"" $policy_file
            yq -i ".receiver.emails[$i].note = \"$note\"" $policy_file
            is_update="true"
        fi
    done
    # add
    if [[ "$is_update" == "false" ]] ; then
        yq -i ".receiver.emails[$(($receiver_email_count_minus_one + 1))].address = \"$address\"" $policy_file
        yq -i ".receiver.emails[$(($receiver_email_count_minus_one + 1))].note = \"$note\"" $policy_file
    fi

    # apply the changes
    $HEX_CFG apply $input_dir
    local ret=$?
    RemoveTempFiles
    return $ret
}

alert_put_setting_receiver_slack()
{
    # input format: {
    #   url: "",
    #   username: "",
    #   description: "",
    #   workspace: "",
    #   channel: "",
    # }

    # process inputs
    local input=${1:-""}
    local url=$(echo $input | jq -r '.url')
    local username=$(echo $input | jq -r '.username')
    local description=$(echo $input | jq -r '.description')
    local workspace=$(echo $input | jq -r '.workspace')
    local channel=$(echo $input | jq -r '.channel')

    # prepare the environment
    local input_dir=$(MakeTempDir)

    # prepare the policy file
    mkdir -p "$input_dir/alert_setting"
    cp -f "/etc/policies/alert_setting/alert_setting1_0.yml" "$input_dir/alert_setting/"
    local policy_file="$input_dir/alert_setting/alert_setting1_0.yml"
    local receiver_slack_count_minus_one=$(($(yq '.receiver.slacks | length' $policy_file) - 1))
    local is_update="false"
    # update
    for i in $(seq 0 "$receiver_slack_count_minus_one") ; do
        if [[ "$url" == "$(yq ".receiver.slacks[$i].url" $policy_file)" ]] ; then
            yq -i ".receiver.slacks[$i].url = \"$url\"" $policy_file
            yq -i ".receiver.slacks[$i].username = \"$username\"" $policy_file
            yq -i ".receiver.slacks[$i].description = \"$description\"" $policy_file
            yq -i ".receiver.slacks[$i].workspace = \"$workspace\"" $policy_file
            yq -i ".receiver.slacks[$i].channel = \"$channel\"" $policy_file
            is_update="true"
        fi
    done
    # add
    if [[ "$is_update" == "false" ]] ; then
        yq -i ".receiver.slacks[$(($receiver_slack_count_minus_one + 1))].url = \"$url\"" $policy_file
        yq -i ".receiver.slacks[$(($receiver_slack_count_minus_one + 1))].username = \"$username\"" $policy_file
        yq -i ".receiver.slacks[$(($receiver_slack_count_minus_one + 1))].description = \"$description\"" $policy_file
        yq -i ".receiver.slacks[$(($receiver_slack_count_minus_one + 1))].workspace = \"$workspace\"" $policy_file
        yq -i ".receiver.slacks[$(($receiver_slack_count_minus_one + 1))].channel = \"$channel\"" $policy_file
    fi

    # apply the changes
    $HEX_CFG apply $input_dir
    local ret=$?
    RemoveTempFiles
    return $ret
}

alert_add_update_setting_receiver_exec_shell()
{
    # the shell should be under /var/response
    # the file name should be $1.shell
    # $1: name

    # process inputs
    local name=${1:-""}
    if [[ "$name" == "" ]] ; then
        return 1
    fi

    # prepare the environment
    cp -f "/var/response/$name.shell" "/var/alert_resp/exec_$name.shell"
    local input_dir=$(MakeTempDir)

    # prepare the policy file
    mkdir -p "$input_dir/alert_setting"
    cp -f "/etc/policies/alert_setting/alert_setting1_0.yml" "$input_dir/alert_setting/"
    local policy_file="$input_dir/alert_setting/alert_setting1_0.yml"
    local receiver_exec_shell_count_minus_one=$(($(yq '.receiver.execs.shells | length' $policy_file) - 1))
    local is_update="false"
    # update
    for i in $(seq 0 "$receiver_exec_shell_count_minus_one") ; do
        if [[ "$name" == "$(yq ".receiver.execs.shells[$i].name" $policy_file)" ]] ; then
            yq -i ".receiver.execs.shells[$i].name = \"$name\"" $policy_file
            is_update="true"
        fi
    done
    # add
    if [[ "$is_update" == "false" ]] ; then
        yq -i ".receiver.execs.shells[$(($receiver_exec_shell_count_minus_one + 1))].name = \"$name\"" $policy_file
    fi

    # apply the changes
    $HEX_CFG apply $input_dir
    local ret=$?
    RemoveTempFiles
    return $ret
}

alert_delete_setting_sender_email()
{
    # prepare the environment
    local input_dir=$(MakeTempDir)

    # prepare the policy file
    mkdir -p "$input_dir/alert_setting"
    cp -f "/etc/policies/alert_setting/alert_setting1_0.yml" "$input_dir/alert_setting/"
    local policy_file="$input_dir/alert_setting/alert_setting1_0.yml"
    yq -i '.sender.email.host = ""' $policy_file
    yq -i '.sender.email.port = ""' $policy_file
    yq -i '.sender.email.username = ""' $policy_file
    yq -i '.sender.email.password = ""' $policy_file
    yq -i '.sender.email.from = ""' $policy_file

    # apply the changes
    $HEX_CFG apply $input_dir
    local ret=$?
    RemoveTempFiles
    return $ret
}

alert_delete_setting_receiver_email()
{
    # input format: {
    #   address: "",
    # }

    # process inputs
    local input=${1:-""}
    local address=$(echo $input | jq -r '.address')

    # prepare the environment
    local input_dir=$(MakeTempDir)

    # prepare the policy file
    mkdir -p "$input_dir/alert_setting"
    cp -f "/etc/policies/alert_setting/alert_setting1_0.yml" "$input_dir/alert_setting/"
    local setting_policy_file="$input_dir/alert_setting/alert_setting1_0.yml"
    local receiver_email_count_minus_one=$(($(yq '.receiver.emails | length' $setting_policy_file) - 1))
    for i in $(seq 0 "$receiver_email_count_minus_one") ; do
        if [[ "$address" == "$(yq ".receiver.emails[$i].address" $setting_policy_file)" ]] ; then
            yq -i "del(.receiver.emails[$i])" $setting_policy_file
        fi
    done

    # delete on cascade
    mkdir -p "$input_dir/alert_resp"
    cp -f "/etc/policies/alert_resp/alert_resp2_0.yml" "$input_dir/alert_resp/"
    local trigger_policy_file="$input_dir/alert_resp/alert_resp2_0.yml"
    local trigger_count_minus_one=$(($(yq '.triggers | length' $trigger_policy_file) - 1))
    for i in $(seq 0 "$trigger_count_minus_one") ; do
        local email_count_minus_one=$(($(yq ".triggers[$i].responses.emails | length" $trigger_policy_file) - 1))
        for j in $(seq 0 "$email_count_minus_one") ; do
            if [[ "$address" == "$(yq ".triggers[$i].responses.emails[$j].address" $trigger_policy_file)" ]] ; then
                yq -i "del(.triggers[$i].responses.emails[$j])" $trigger_policy_file
            fi
        done
    done

    # apply the changes
    $HEX_CFG apply $input_dir
    local ret=$?
    RemoveTempFiles
    return $ret
}

alert_delete_setting_receiver_slack()
{
    # input format: {
    #   url: "",
    # }

    # process inputs
    local input=${1:-""}
    local url=$(echo $input | jq -r '.url')

    # prepare the environment
    local input_dir=$(MakeTempDir)

    # prepare the policy file
    mkdir -p "$input_dir/alert_setting"
    cp -f "/etc/policies/alert_setting/alert_setting1_0.yml" "$input_dir/alert_setting/"
    local setting_policy_file="$input_dir/alert_setting/alert_setting1_0.yml"
    local receiver_slack_count_minus_one=$(($(yq '.receiver.slacks | length' $setting_policy_file) - 1))
    for i in $(seq 0 "$receiver_slack_count_minus_one") ; do
        if [[ "$url" == "$(yq ".receiver.slacks[$i].url" $setting_policy_file)" ]] ; then
            yq -i "del(.receiver.slacks[$i])" $setting_policy_file
        fi
    done

    # delete on cascade
    mkdir -p "$input_dir/alert_resp"
    cp -f "/etc/policies/alert_resp/alert_resp2_0.yml" "$input_dir/alert_resp/"
    local trigger_policy_file="$input_dir/alert_resp/alert_resp2_0.yml"
    local trigger_count_minus_one=$(($(yq '.triggers | length' $trigger_policy_file) - 1))
    for i in $(seq 0 "$trigger_count_minus_one") ; do
        local slack_count_minus_one=$(($(yq ".triggers[$i].responses.slacks | length" $trigger_policy_file) - 1))
        for j in $(seq 0 "$slack_count_minus_one") ; do
            if [[ "$url" == "$(yq ".triggers[$i].responses.slacks[$j].url" $trigger_policy_file)" ]] ; then
                yq -i "del(.triggers[$i].responses.slacks[$j])" $trigger_policy_file
            fi
        done
    done

    # apply the changes
    $HEX_CFG apply $input_dir
    local ret=$?
    RemoveTempFiles
    return $ret
}

alert_get_trigger()
{
    # output format: [
    #   {
    #     name: "",
    #     enabled: true,
    #     topic: "",
    #     match: "",
    #     description: "",
    #     emails: [
    #       {
    #         address: ""
    #       }
    #     ],
    #     slacks: [
    #       {
    #         url: ""
    #       }
    #     ],
    #     execs: {
    #       shells: [
    #         {
    #           name: ""
    #         }
    #       ],
    #       bins: [
    #         {
    #           name: ""
    #         }
    #       ]
    #     }
    #   }
    # ]

    # load the tunings into the env
    local trigger_count_minus_one=$(($(grep -E "kapacitor.alert.resp.[0-9]+.name" $SETTINGS_TXT | wc -l) - 1))
    for i in $(seq 0 "$trigger_count_minus_one") ; do
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.resp.$i.name"
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.resp.$i.enabled"
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.resp.$i.topic"
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.resp.$i.match"
        source hex_tuning $SETTINGS_TXT "kapacitor.alert.resp.$i.description"

        # email
        local email_count_minus_one=$(($(grep -E "kapacitor.alert.resp.$i.responses.emails.[0-9]+.address" $SETTINGS_TXT | wc -l) - 1))
        for j in $(seq 0 "$email_count_minus_one") ; do
            source hex_tuning $SETTINGS_TXT "kapacitor.alert.resp.$i.responses.emails.$j.address"
        done

        # slack
        local slack_count_minus_one=$(($(grep -E "kapacitor.alert.resp.$i.responses.slacks.[0-9]+.url" $SETTINGS_TXT | wc -l) - 1))
        for j in $(seq 0 "$slack_count_minus_one") ; do
            source hex_tuning $SETTINGS_TXT "kapacitor.alert.resp.$i.responses.slacks.$j.url"
        done

        # exec shell
        local exec_shell_count_minus_one=$(($(grep -E "kapacitor.alert.resp.$i.responses.execs.shells.[0-9]+.name" $SETTINGS_TXT | wc -l) - 1))
        for j in $(seq 0 "$exec_shell_count_minus_one") ; do
            source hex_tuning $SETTINGS_TXT "kapacitor.alert.resp.$i.responses.execs.shells.$j.name"
        done

        # exec bin
        local exec_bin_count_minus_one=$(($(grep -E "kapacitor.alert.resp.$i.responses.execs.bins.[0-9]+.name" $SETTINGS_TXT | wc -l) - 1))
        for j in $(seq 0 "$exec_bin_count_minus_one") ; do
            source hex_tuning $SETTINGS_TXT "kapacitor.alert.resp.$i.responses.execs.bins.$j.name"
        done
    done

    # format the JSON string
    local output_count=0
    local output="["
    for i in $(seq 0 "$trigger_count_minus_one") ; do
        local name_key="T_kapacitor_alert_resp_${i}_name"
        local enabled_key="T_kapacitor_alert_resp_${i}_enabled"
        local topic_key="T_kapacitor_alert_resp_${i}_topic"
        local match_key="T_kapacitor_alert_resp_${i}_match"
        local description_key="T_kapacitor_alert_resp_${i}_description"

        local enabled="false"
        if [[ "${!enabled_key}" == "true" ]] ; then
            enabled="true"
        fi
        local match=${!match_key//_/\"}

        # email
        local e_count=0
        local e="["
        local email_count_minus_one=$(($(grep -E "kapacitor.alert.resp.$i.responses.emails.[0-9]+.address" $SETTINGS_TXT | wc -l) - 1))
        for j in $(seq 0 "$email_count_minus_one") ; do
            local address_key="T_kapacitor_alert_resp_${i}_responses_emails_${j}_address"
            if [[ "${!address_key}" == "" ]] ; then
                continue
            fi

            if [[ "$e_count" -gt 0 ]] ; then
                e+=","
            fi

            ((e_count++))
            e+=$(jq -c -n \
                --arg address "${!address_key}" \
                '{address: $address}')
        done
        e+="]"

        # slack
        local s_count=0
        local s="["
        local slack_count_minus_one=$(($(grep -E "kapacitor.alert.resp.$i.responses.slacks.[0-9]+.url" $SETTINGS_TXT | wc -l) - 1))
        for j in $(seq 0 "$slack_count_minus_one") ; do
            local url_key="T_kapacitor_alert_resp_${i}_responses_slacks_${j}_url"
            if [[ "${!url_key}" == "" ]] ; then
                continue
            fi

            if [[ "$s_count" -gt 0 ]] ; then
                s+=","
            fi

            ((s_count++))
            s+=$(jq -c -n \
                --arg url "${!url_key}" \
                '{url: $url}')
        done
        s+="]"

        # exec shell
        local es_count=0
        local es="["
        local exec_shell_count_minus_one=$(($(grep -E "kapacitor.alert.resp.$i.responses.execs.shells.[0-9]+.name" $SETTINGS_TXT | wc -l) - 1))
        for j in $(seq 0 "$exec_shell_count_minus_one") ; do
            local es_name_key="T_kapacitor_alert_resp_${i}_responses_execs_shells_${j}_name"
            if [[ "${!es_name_key}" == "" ]] ; then
                continue
            fi

            if [[ "$es_count" -gt 0 ]] ; then
                es+=","
            fi

            ((es_count++))
            es+=$(jq -c -n \
                --arg name "${!es_name_key}" \
                '{name: $name}')
        done
        es+="]"

        # exec bin
        local eb_count=0
        local eb="["
        local exec_bin_count_minus_one=$(($(grep -E "kapacitor.alert.resp.$i.responses.execs.bins.[0-9]+.name" $SETTINGS_TXT | wc -l) - 1))
        for j in $(seq 0 "$exec_bin_count_minus_one") ; do
            local eb_name_key="T_kapacitor_alert_resp_${i}_responses_execs_bins_${j}_name"
            if [[ "${!eb_name_key}" == "" ]] ; then
                continue
            fi

            if [[ "$eb_count" -gt 0 ]] ; then
                eb+=","
            fi

            ((eb_count++))
            eb+=$(jq -c -n \
                --arg name "${!eb_name_key}" \
                '{name: $name}')
        done
        eb+="]"

        if [[ "$output_count" -gt 0 ]] ; then
            output+=","
        fi

        ((output_count++))
        output+=$(jq -c -n \
            --arg name "${!name_key}" \
            --arg enabled "$enabled" \
            --arg topic "${!topic_key}" \
            --arg match "$match" \
            --arg description "${!description_key}" \
            --argjson emails "$e" \
            --argjson slacks "$s" \
            --argjson execShells "$es" \
            --argjson execBins "$eb" \
            '{name: $name, enabled: $enabled | test("true"), topic: $topic, match: $match, description: $description, emails: $emails, slacks: $slacks, execs: {shells: $execShells, bins: $execBins}}')
    done
    output+="]"

    # output
    jq -c -n "$output"
}

alert_add_update_trigger_exec()
{
    # $1: name
    # $2: enabled (true/false)
    # $3: topic
    # $4: match
    # $5: description
    # $6: name
    # $7: type

    # process inputs
    local name=${1:-""}
    local enabled=${2:-""}
    if [[ "x$enabled" == "xtrue" ]] ; then
        enabled="true"
    else
        enabled="false"
    fi
    local topic=${3:-""}
    local match=${4:-""}
    local description=${5:-""}
    local name=${6:-""}
    local type=${7:-""}
    if [[ "$type" != "shell" && "$type" != "bin" ]] ; then
        return 1
    fi

    # prepare the environment
    local input_dir=$(MakeTempDir)

    # prepare the policy file
    local setting_policy_file="/etc/policies/alert_setting/alert_setting1_0.yml"
    mkdir -p "$input_dir/alert_resp"
    cp -f "/etc/policies/alert_resp/alert_resp2_0.yml" "$input_dir/alert_resp/"
    local trigger_policy_file="$input_dir/alert_resp/alert_resp2_0.yml"
    local trigger_count_minus_one=$(($(yq '.triggers | length' $trigger_policy_file) - 1))
    local is_update="false"
    # update
    for i in $(seq 0 "$trigger_count_minus_one") ; do
        if [[ "$name" == "$(yq ".triggers[$i].name" $trigger_policy_file)" ]] ; then
            yq -i ".triggers[$i].name = \"$name\"" $trigger_policy_file
            yq -i ".triggers[$i].enabled = \"$enabled\"" $trigger_policy_file
            yq -i ".triggers[$i].topic = \"$topic\"" $trigger_policy_file
            yq -i ".triggers[$i].match = \"${match//\"/\\\"}\"" $trigger_policy_file
            yq -i ".triggers[$i].description = \"$description\"" $trigger_policy_file

            if [[ "$type" == "shell" ]] ; then
                # exec shell
                # check if the exec shell name is in the alert_setting policy
                local setting_exec_shell_count_minus_one=$(($(yq '.receiver.execs.shells | length' $setting_policy_file) - 1))
                local does_exist="false"
                for j in $(seq 0 "$setting_exec_shell_count_minus_one") ; do
                    if [[ "$name" == "$(yq ".receiver.execs.shells[$j].name" $setting_policy_file)" ]] ; then
                        does_exist="true"
                    fi
                done
                if [[ "$does_exist" == "false" ]] ; then
                    continue
                fi

                # add exec shell to the trigger
                local trigger_exec_shell_count_minus_one=$(($(yq ".triggers[$i].responses.execs.shells | length" $trigger_policy_file) - 1))
                does_exist="false"
                for j in $(seq 0 "$trigger_exec_shell_count_minus_one") ; do
                    if [[ "$name" == "$(yq ".triggers[$i].responses.execs.shells[$j].name" $setting_policy_file)" ]] ; then
                        does_exist="true"
                    fi
                done
                if [[ "$does_exist" == "false" ]] ; then
                    yq -i ".triggers[$i].responses.execs.shells[$(($trigger_exec_shell_count_minus_one + 1))].name = \"$name\"" $trigger_policy_file
                fi
            else
                # exec bin
                # check if the exec bin name is in the alert_setting policy
                local setting_exec_bin_count_minus_one=$(($(yq '.receiver.execs.bins | length' $setting_policy_file) - 1))
                local does_exist="false"
                for j in $(seq 0 "$setting_exec_bin_count_minus_one") ; do
                    if [[ "$name" == "$(yq ".receiver.execs.bins[$j].name" $setting_policy_file)" ]] ; then
                        does_exist="true"
                    fi
                done
                if [[ "$does_exist" == "false" ]] ; then
                    continue
                fi

                # add exec shell to the trigger
                local trigger_exec_bin_count_minus_one=$(($(yq ".triggers[$i].responses.execs.bins | length" $trigger_policy_file) - 1))
                does_exist="false"
                for j in $(seq 0 "$trigger_exec_bin_count_minus_one") ; do
                    if [[ "$name" == "$(yq ".triggers[$i].responses.execs.bins[$j].name" $setting_policy_file)" ]] ; then
                        does_exist="true"
                    fi
                done
                if [[ "$does_exist" == "false" ]] ; then
                    yq -i ".triggers[$i].responses.execs.bins[$(($trigger_exec_bin_count_minus_one + 1))].name = \"$name\"" $trigger_policy_file
                fi
            fi

            is_update="true"
        fi
    done
    # add
    if [[ "$is_update" == "false" ]] ; then
        yq -i ".triggers[$(($trigger_count_minus_one + 1))].name = \"$name\"" $trigger_policy_file
        yq -i ".triggers[$(($trigger_count_minus_one + 1))].enabled = \"$enabled\"" $trigger_policy_file
        yq -i ".triggers[$(($trigger_count_minus_one + 1))].topic = \"$topic\"" $trigger_policy_file
        yq -i ".triggers[$(($trigger_count_minus_one + 1))].match = \"$match\"" $trigger_policy_file
        yq -i ".triggers[$(($trigger_count_minus_one + 1))].description = \"$description\"" $trigger_policy_file

        if [[ "$type" == "shell" ]] ; then
            # exec shell
            # check if the exec shell name is in the alert_setting policy
            local setting_exec_shell_count_minus_one=$(($(yq '.receiver.execs.shells | length' $setting_policy_file) - 1))
            local does_exist="false"
            for i in $(seq 0 "$setting_exec_shell_count_minus_one") ; do
                if [[ "$name" == "$(yq ".receiver.execs.shells[$i].name" $setting_policy_file)" ]] ; then
                    does_exist="true"
                fi
            done
            if [[ "$does_exist" == "false" ]] ; then
                continue
            fi

            # add exec shell to the trigger
            yq -i ".triggers[$(($trigger_count_minus_one + 1))].responses.execs.shells[0].name = \"$name\"" $trigger_policy_file
        else
            # exec bin
            # check if the exec bin name is in the alert_setting policy
            local setting_exec_bin_count_minus_one=$(($(yq '.receiver.execs.bins | length' $setting_policy_file) - 1))
            local does_exist="false"
            for i in $(seq 0 "$setting_exec_bin_count_minus_one") ; do
                if [[ "$name" == "$(yq ".receiver.execs.bins[$i].name" $setting_policy_file)" ]] ; then
                    does_exist="true"
                fi
            done
            if [[ "$does_exist" == "false" ]] ; then
                continue
            fi

            # add exec shell to the trigger
            yq -i ".triggers[$(($trigger_count_minus_one + 1))].responses.execs.bins[0].name = \"$name\"" $trigger_policy_file
        fi
    fi

    # apply the changes
    $HEX_CFG apply $input_dir
    local ret=$?
    RemoveTempFiles
    return $ret
}

alert_put_trigger()
{
    # input format: {
    #   name: "",
    #   enabled: true, // boolean
    #   topic: "",
    #   match: "",
    #   description: "",
    #   responses: {
    #     emails: ["", ""],
    #     slacks: ["", ""],
    #   },
    # }
    #
    # output format: {
    #   success: true,
    #   message: "",
    # }

    # process inputs
    local input=${1:-""}
    local name=$(echo $input | jq -r '.name')
    local enabled=$(echo $input | jq -r '.enabled')
    if [[ "x$enabled" == "xtrue" ]] ; then
        enabled="true"
    else
        enabled="false"
    fi
    local topic=$(echo $input | jq -r '.topic')
    local match=$(echo $input | jq -r '.match')
    local description=$(echo $input | jq -r '.description')

    # some limitations on name
    if [[ "$name" == "admin-notify" ]] ; then
        topic="events"
        match="\"severity\" == 'W' OR \"severity\" == 'E' OR \"severity\" == 'C'"
    elif [[ "$name" == "instance-notify" ]] ; then
        topic="instance-events"
        match="\"severity\" == 'W' OR \"severity\" == 'C'"
    else
        jq -c -n \
            '{success: false, message: "the trigger name is not supported"}'
        return 1
    fi

    # prepare the environment
    local input_dir=$(MakeTempDir)

    # prepare the policy file
    local setting_policy_file="/etc/policies/alert_setting/alert_setting1_0.yml"
    mkdir -p "$input_dir/alert_resp"
    cp -f "/etc/policies/alert_resp/alert_resp2_0.yml" "$input_dir/alert_resp/"
    local trigger_policy_file="$input_dir/alert_resp/alert_resp2_0.yml"
    local trigger_count_minus_one=$(($(yq '.triggers | length' $trigger_policy_file) - 1))
    local is_update="false"
    # update
    for i in $(seq 0 "$trigger_count_minus_one") ; do
        if [[ "$name" == "$(yq ".triggers[$i].name" $trigger_policy_file)" ]] ; then
            yq -i ".triggers[$i].name = \"$name\"" $trigger_policy_file
            yq -i ".triggers[$i].enabled = \"$enabled\"" $trigger_policy_file
            yq -i ".triggers[$i].topic = \"$topic\"" $trigger_policy_file
            yq -i ".triggers[$i].match = \"${match//\"/\\\"}\"" $trigger_policy_file
            yq -i ".triggers[$i].description = \"$description\"" $trigger_policy_file

            # email
            yq -i "del(.triggers[$i].responses.emails)" $trigger_policy_file
            local email_count_minus_one=$(($(echo $input | jq -r '.responses.emails | length') - 1))
            local new_email_index="0"
            for j in $(seq 0 "$email_count_minus_one") ; do
                local email=$(echo $input | jq -r ".responses.emails[$j]")

                # check if the email is in the alert_setting policy
                local setting_email_count_minus_one=$(($(yq '.receiver.emails | length' $setting_policy_file) - 1))
                local does_exist="false"
                for k in $(seq 0 "$setting_email_count_minus_one") ; do
                    if [[ "$email" == "$(yq ".receiver.emails[$k].address" $setting_policy_file)" ]] ; then
                        does_exist="true"
                    fi
                done
                if [[ "$does_exist" == "false" ]] ; then
                    continue
                fi

                yq -i ".triggers[$i].responses.emails[$new_email_index].address = \"$email\"" $trigger_policy_file
                ((new_email_index++))
            done

            # slack
            yq -i "del(.triggers[$i].responses.slacks)" $trigger_policy_file
            local slack_count_minus_one=$(($(echo $input | jq -r '.responses.slacks | length') - 1))
            local new_slack_index="0"
            for j in $(seq 0 "$slack_count_minus_one") ; do
                local slack=$(echo $input | jq -r ".responses.slacks[$j]")

                # check if the slack is in the alert_setting policy
                local setting_slack_count_minus_one=$(($(yq '.receiver.slacks | length' $setting_policy_file) - 1))
                local does_exist="false"
                for k in $(seq 0 "$setting_slack_count_minus_one") ; do
                    if [[ "$slack" == "$(yq ".receiver.slacks[$k].url" $setting_policy_file)" ]] ; then
                        does_exist="true"
                    fi
                done
                if [[ "$does_exist" == "false" ]] ; then
                    continue
                fi

                yq -i ".triggers[$i].responses.slacks[$new_slack_index].url = \"$slack\"" $trigger_policy_file
                ((new_slack_index++))
            done

            is_update="true"
        fi
    done
    # add
    if [[ "$is_update" == "false" ]] ; then
        yq -i ".triggers[$(($trigger_count_minus_one + 1))].name = \"$name\"" $trigger_policy_file
        yq -i ".triggers[$(($trigger_count_minus_one + 1))].enabled = \"$enabled\"" $trigger_policy_file
        yq -i ".triggers[$(($trigger_count_minus_one + 1))].topic = \"$topic\"" $trigger_policy_file
        yq -i ".triggers[$(($trigger_count_minus_one + 1))].match = \"$match\"" $trigger_policy_file
        yq -i ".triggers[$(($trigger_count_minus_one + 1))].description = \"$description\"" $trigger_policy_file

        # email
        yq -i "del(.triggers[$(($trigger_count_minus_one + 1))].responses.emails)" $trigger_policy_file
        local email_count_minus_one=$(($(echo $input | jq -r '.responses.emails | length') - 1))
        local new_email_index="0"
        for j in $(seq 0 "$email_count_minus_one") ; do
            local email=$(echo $input | jq -r ".responses.emails[$j]")

            # check if the email is in the alert_setting policy
            local setting_email_count_minus_one=$(($(yq '.receiver.emails | length' $setting_policy_file) - 1))
            local does_exist="false"
            for k in $(seq 0 "$setting_email_count_minus_one") ; do
                if [[ "$email" == "$(yq ".receiver.emails[$k].address" $setting_policy_file)" ]] ; then
                    does_exist="true"
                fi
            done
            if [[ "$does_exist" == "false" ]] ; then
                continue
            fi

            yq -i ".triggers[$(($trigger_count_minus_one + 1))].responses.emails[$new_email_index].address = \"$email\"" $trigger_policy_file
            ((new_email_index++))
        done

        # slack
        yq -i "del(.triggers[$(($trigger_count_minus_one + 1))].responses.slacks)" $trigger_policy_file
        local slack_count_minus_one=$(($(echo $input | jq -r '.responses.slacks | length') - 1))
        local new_slack_index="0"
        for j in $(seq 0 "$slack_count_minus_one") ; do
            local slack=$(echo $input | jq -r ".responses.slacks[$j]")

            # check if the slack is in the alert_setting policy
            local setting_slack_count_minus_one=$(($(yq '.receiver.slacks | length' $setting_policy_file) - 1))
            local does_exist="false"
            for k in $(seq 0 "$setting_slack_count_minus_one") ; do
                if [[ "$slack" == "$(yq ".receiver.slacks[$k].url" $setting_policy_file)" ]] ; then
                    does_exist="true"
                fi
            done
            if [[ "$does_exist" == "false" ]] ; then
                continue
            fi

            yq -i ".triggers[$(($trigger_count_minus_one + 1))].responses.slacks[$new_slack_index].url = \"$slack\"" $trigger_policy_file
            ((new_slack_index++))
        done
    fi

    # apply the changes
    $HEX_CFG apply $input_dir
    local ret=$?
    RemoveTempFiles
    jq -c -n \
        '{success: true, message: ""}'
    return $ret
}

alert_get_full_trigger()
{
    # output format: {
    #   setting: {
    #     titlePrefix: "",
    #     sender: {
    #       email: {
    #         host: "",
    #         port: "",
    #         username: "",
    #         password: "",
    #         from: ""
    #       }
    #     },
    #     receiver: {
    #       emails: [
    #         {
    #           address: "",
    #           note: ""
    #         }
    #       ],
    #       slacks: [
    #         {
    #           url: "",
    #           username: "",
    #           description: "",
    #           workspace: "",
    #           channel: ""
    #         }
    #       ]
    #     }
    #   },
    #   triggers: [
    #     {
    #       name: "",
    #       enabled: true,
    #       topic: "",
    #       match: "",
    #       description: "",
    #       emails: [
    #         {
    #           address: "",
    #           note: ""
    #         }
    #       ],
    #       slacks: [
    #         {
    #           url: "",
    #           username: "",
    #           description: "",
    #           workspace: "",
    #           channel: ""
    #         }
    #       ],
    #       execs: {
    #         shells: [
    #           {
    #             name: ""
    #           }
    #         ],
    #         bins: [
    #           {
    #             name: ""
    #           }
    #         ]
    #       }
    #     }
    #   ]
    # }

    # join
    local setting=$(alert_get_setting)
    local triggers=$(alert_get_trigger)
    local full_triggers="$triggers"
    local trigger_count_minus_one=$(($(echo $triggers | jq -r 'length') - 1))
    for i in $(seq 0 "$trigger_count_minus_one") ; do
        # email
        local email_count_minus_one=$(($(echo $triggers | jq -r ".[$i].emails | length") - 1))
        for j in $(seq 0 "$email_count_minus_one") ; do
            local setting_email_count_minus_one=$(($(echo $setting | jq -r ".receiver.emails | length") - 1))
            for k in $(seq 0 "$setting_email_count_minus_one") ; do
                local email=$(echo $triggers | jq -r ".[$i].emails[$j].address")
                local setting_email=$(echo $setting | jq -r ".receiver.emails[$k].address")
                if [[ "$email" == "$setting_email" ]] ; then
                    local note=$(echo $setting | jq -r ".receiver.emails[$k].note")
                    full_triggers=$(echo $full_triggers | jq ".[$i].emails[$j].note = \"$note\"")
                fi
            done
        done

        # slack
        local slack_count_minus_one=$(($(echo $triggers | jq -r ".[$i].slacks | length") - 1))
        for j in $(seq 0 "$slack_count_minus_one") ; do
            local setting_slack_count_minus_one=$(($(echo $setting | jq -r ".receiver.slacks | length") - 1))
            for k in $(seq 0 "$setting_slack_count_minus_one") ; do
                local slack=$(echo $triggers | jq -r ".[$i].slacks[$j].url")
                local setting_slack=$(echo $setting | jq -r ".receiver.slacks[$k].url")
                if [[ "$slack" == "$setting_slack" ]] ; then
                    local username=$(echo $setting | jq -r ".receiver.slacks[$k].username")
                    full_triggers=$(echo $full_triggers | jq ".[$i].slacks[$j].username = \"$username\"")
                    local description=$(echo $setting | jq -r ".receiver.slacks[$k].description")
                    full_triggers=$(echo $full_triggers | jq ".[$i].slacks[$j].description = \"$description\"")
                    local workspace=$(echo $setting | jq -r ".receiver.slacks[$k].workspace")
                    full_triggers=$(echo $full_triggers | jq ".[$i].slacks[$j].workspace = \"$workspace\"")
                    local channel=$(echo $setting | jq -r ".receiver.slacks[$k].channel")
                    full_triggers=$(echo $full_triggers | jq ".[$i].slacks[$j].channel = \"$channel\"")
                fi
            done
        done
    done

    # output
    jq -c -n \
        --argjson setting "$setting" \
        --argjson triggers "$full_triggers" \
        '{setting: $setting, triggers: $triggers}'
}
