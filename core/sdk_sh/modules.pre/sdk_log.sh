# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

log_debug()
{
    if [ -z "$1" ] ; then
        return 0
    fi

    logger -p user.debug -t "$PROG" "debug: ${1}"
}

log_info()
{
    if [ -z "$1" ] ; then
        return 0
    fi

    logger -p user.info -t "$PROG" "info: ${1}"
}

log_warning()
{
    if [ -z "$1" ] ; then
        return 0
    fi

    logger -p user.warning -t "$PROG" "warning: ${1}"
}

log_error()
{
    if [ -z "$1" ] ; then
        return 0
    fi

    logger -p user.err -t "$PROG" "error: ${1}"
}
