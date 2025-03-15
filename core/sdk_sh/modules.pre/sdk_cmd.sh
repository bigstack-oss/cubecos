# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

cmd()
{
    cmd=$1
    shift 1
    eval "\$$cmd $*"
}
