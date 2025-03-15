# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

rabbitmq_queue_status()
{
    local rbt_ver=$(rabbitmqctl --version)
    cp -f /var/lib/rabbitmq/.erlang.cookie /root/
    cp -f /var/lib/rabbitmq/.erlang.cookie /tmp/
    rabbitmqctl list_queues -s | awk '{ print $1 }' | xargs -L1 -P8 /usr/lib/rabbitmq/lib/rabbitmq_server-${rbt_ver}/escript/rabbitmq-queues quorum_status
}

rabbitmq_quorum_queue_set()
{
    local name=$1
    local rbt_ver=$(rabbitmqctl --version)

    readarray ctrl_array <<<"$(cubectl node list -r control -j | jq -r .[].hostname | sort)"
    declare -p ctrl_array > /dev/null
    for ctrl_entry in "${ctrl_array[@]}" ; do
        local ctrl=$(echo $ctrl_entry | head -c -1)
        env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/lib/rabbitmq/lib/rabbitmq_server-${rbt_ver}/escript/rabbitmq-queues add_member $name rabbit@$ctrl -q
    done
}

rabbitmq_queue_repair()
{
    cp -f /var/lib/rabbitmq/.erlang.cookie /root/
    cp -f /var/lib/rabbitmq/.erlang.cookie /tmp/.erlang.cookie
    env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/sbin/rabbitmqctl list_queues -s | awk '{ print $1 }' | xargs -L1 -P8 $HEX_SDK rabbitmq_quorum_queue_set
}

rabbitmq_unhealthy_queue_clear()
{
    readarray queue_array <<<"$(env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/sbin/rabbitmqctl list_unresponsive_queues | sed '1,2d')"
    declare -p queue_array > /dev/null
    for queue in "${queue_array[@]}" ; do
        local q=$(echo $queue | head -c -1)
        if [ -n "$q" ]; then
            env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/sbin/rabbitmqctl eval '{ok,Q} = rabbit_amqqueue:lookup(rabbit_misc:r(<<"/">>,queue,<<"'$q'">>)),rabbit_amqqueue:delete_crashed(Q).'
        fi
    done

    readarray orphant_array <<<"$(env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/sbin/rabbitmqctl list_queues consumers name | sed '1,3d' | grep "^0" | awk '{print $2}')"
    declare -p orphant_array > /dev/null
    for orphant in "${orphant_array[@]}" ; do
        local o=$(echo $orphant | head -c -1)
        if [ -n "$o" ]; then
            env LANG=en_US.utf8 HOSTNAME=$(hostname) /usr/sbin/rabbitmqctl delete_queue $o 2>&1 >/dev/null
        fi
    done
}
