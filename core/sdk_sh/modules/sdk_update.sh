# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

update_security_list()
{
    Quiet -n $DNF -q updateinfo info --security
}

update_security_update()
{
    local type=${1:-all}
    local id=$2
    if [ "$type" == "all" ] ; then
        Quiet -n $DNF update --security
    elif [ "$type" == "advisory" ] ; then
        Quiet -n $DNF update --advisory=$id
    elif [ "$type" == "cve" ] ; then
        Quiet -n $DNF update --cve=$id
    fi
}
