# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

toggle_health_check()
{
    local srv=$1
    if [ "x$srv" == "x" ] ; then
        for chk in $($HEX_SDK health 2>/dev/null | grep "^health_.*_check$") ; do
            srv=$(echo $chk | sed -e "s/^health_//" -e "s/_check$//")
            mkf=$HEX_STATE_DIR/health_${srv}_check_disabled
            if [ -e $mkf ] ; then
                status=disabled
            else
                status=enabled
            fi
            printf "%24s: %s\n" "$srv" "$status"
        done
    else
        $HEX_SDK health 2>/dev/null | grep -q "^health_${srv}_check$" || Error "no health_${srv}_check"
        local mkf=$HEX_STATE_DIR/health_${srv}_check_disabled
        if [ -e $mkf ] ; then
            Quiet -n cubectl node exec -pn rm -f $mkf
            status=enabled
        else
            Quiet -n cubectl node exec -pn touch $mkf
            status=disabled
        fi
        printf "health_%s_check is %s\n" "$srv" "$status"
    fi
}
