# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

ntp_makestep()
{
    if systemctl restart chronyd >/dev/null 2>&1; then
        sleep 5
        /sbin/hwclock -w -u
    fi
}
