# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

remote_systemd_stop()
{
    local host=$1
    shift 1
    ! is_sshable $host || timeout $SRVTO ssh root@$host systemctl stop $@ >/dev/null 2>&1
}

remote_systemd_start()
{
    local host=$1
    shift 1
    if is_sshable $host ; then
        timeout $SRVTO ssh root@$host systemctl reset-failed >/dev/null 2>&1
        timeout $SRVLTO ssh root@$host systemctl start $@ >/dev/null 2>&1
    fi
}

remote_systemd_restart()
{
    local host=$1
    shift 1
    if is_sshable $host ; then
        timeout $SRVTO ssh root@$host systemctl reset-failed >/dev/null 2>&1
        timeout $SRVLTO ssh root@$host systemctl restart $@ >/dev/null 2>&1
    fi
}

remote_run()
{
    local flag=
    local host=$1
    shift 1
    if [ "$VERBOSE" == "1" ] ; then
        if test -t 0 ; then
            flag="-t"
        fi
    fi
    ! is_sshable $host || ssh $flag root@$host $@ 2>/dev/null
}
