# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

_influx()
{
    local db=$1
    shift
    local flag="-database $db"

    if echo "$@" | grep -q -i insert ; then
        for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
            timeout $SRVSTO /usr/bin/influx $flag -host $node -execute "$@" >/dev/null 2>&1 &
        done
        wait $! || true
    else
        if [ "$FORMAT" = "json" ] ; then
            flag+=" -format json -pretty"
        fi

        if ! $INFLUX $flag -execute "$@" 2>/dev/null ; then
            for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
                ! timeout $SRVSTO /usr/bin/influx $flag -host $node -execute "$@" 2>/dev/null || break
            done
        fi
    fi
}

influx_event()
{
    _influx events "$@"
}

influx_event_health()
{
    local component=$1
    local limit=${2:-10}
    local tagfield="component,code,description,node,log"

    [ "$VERBOSE" != "1" ] || tagfield="*"

    if [ "x$1" = "x" ] ; then
        for component in $($HEX_SDK toggle_health_check | cut -d":" -f1) ; do
            influx_event "select $tagfield from health where component='$component' order by desc limit $limit"
        done
    else
        influx_event "select $tagfield from health where component='$component' order by desc limit $limit"
    fi

}


influx_event_system()
{
    local re='^[0-9]+$'
    local limit=10
    local category=
    if [ $# -eq 1 ] ; then
        if [[ $1 =~ $re ]] ; then
            limit=$1
        else
            local category=$1
        fi
    elif [ $# -gt 1 ] ; then
        category=$1
        limit=$2
    fi
    local tagfield="host,node,category,service,severity,message,metadata"

    [ "$VERBOSE" != "1" ] || tagfield="*"

    if [ "x$category" = "x" ] ; then
        influx_event "select * from system order by desc limit $limit"
    else
        influx_event "select $tagfield from system where category='$category' order by desc limit $limit"
    fi
}

influx_event_audit()
{
    local re='^[0-9]+$'
    local limit=10
    local parent=
    if [ $# -eq 1 ] ; then
        if [[ $1 =~ $re ]] ; then
            limit=$1
        else
            local parent=$1
        fi
    elif [ $# -gt 1 ] ; then
        parent=$1
        limit=$2
    fi
    local tagfield="node,grandpa,parent,cmd"

    [ "$VERBOSE" != "1" ] || tagfield="node,grandpa,gpid,parent,ppid,cmd"

    if [ "x$parent" = "x" ] ; then
        influx_event "select $tagfield from audit order by desc limit $limit"
    else
        influx_event "select $tagfield from audit where parent='$parent' order by desc limit $limit"
    fi
}
