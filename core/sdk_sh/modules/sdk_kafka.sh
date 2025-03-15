# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

kafka_stats()
{
    /opt/kafka/bin/kafka-topics.sh --describe --bootstrap-server $HOSTNAME:9095 2>/dev/null
}
