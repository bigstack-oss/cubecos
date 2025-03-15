# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

zookeeper_stats()
{
    local zk_host=$HOSTNAME
    local zk_port=2181

    echo stat | nc $zk_host $zk_port

    printf "\nbroker list\n"
    for i in `echo dump | nc $zk_host $zk_port | grep brokers` ; do
        detail=`/opt/kafka/bin/zookeeper-shell.sh $zk_host:$zk_port <<< "get $i" 2>/dev/null | grep endpoints | jq -r .endpoints[]`
        echo "$i: $detail"
    done
}
