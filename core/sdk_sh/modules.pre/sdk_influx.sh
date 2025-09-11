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
        nohup $HEX_SDK cmd -c "$INFLUX $flag -host \$HOSTNAME -execute '$@'" >/dev/null 2>&1 &
    else
        if [ "x$FORMAT" = "xjson" ] ; then
            flag+=" -format json -pretty"
        fi
        if [ "x$VERBOSE" = "x1" ] ; then
            flag+=" -precision rfc3339"
        fi

        if ! $INFLUX $flag -execute "$@" 2>/dev/null ; then
            for node in "${CUBE_NODE_CONTROL_HOSTNAMES[@]}" ; do
                ! timeout $SRVTO /usr/bin/influx $flag -host $node -execute "$@" 2>/dev/null || break
            done
        fi
    fi
}

influx_event()
{
    _influx events "$@" 2>/dev/null 2>&1
}

influx_event_health()
{
    local component=$1
    local limit=${2:-10}
    local tagfield="component,code,description,node,log"

    [ "x$VERBOSE" != "x1" ] || tagfield="*"

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

    [ "x$VERBOSE" != "x1" ] || tagfield="*"

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
    local pcmd=
    if [ $# -eq 1 ] ; then
        if [[ $1 =~ $re ]] ; then
            limit=$1
        else
            local pcmd=$1
        fi
    elif [ $# -gt 1 ] ; then
        pcmd=$1
        limit=$2
    fi
    local tagfield="node,gcmd,pcmd,cmd"

    [ "x$VERBOSE" != "x1" ] || tagfield="node,gusr,gcmd,gpid,pusr,pcmd,ppid,usr,cmd,pid"

    if [ "x$pcmd" = "x" ] ; then
        influx_event "select $tagfield from audit order by desc limit $limit"
    else
        influx_event "select $tagfield from audit where pcmd='$pcmd' order by desc limit $limit"
    fi
}
