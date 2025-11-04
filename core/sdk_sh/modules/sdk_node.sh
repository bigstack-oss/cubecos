# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

node_boot_status()
{
    # we should not proceed in the following situations
    if [ -f "/etc/appliance/state/strict_mode_error" ] ; then
        return 0
    fi
    if [ ! -f "/etc/appliance/state/configured" ] ; then
        return 0
    fi

    local bootstrap_cube_mode="/etc/appliance/state/boot_mode"
    if [ -f "$bootstrap_cube_mode" ] && grep -q manual "$bootstrap_cube_mode" ; then
        $HEX_CLI -c boot status
    else
        $HEX_CLI -c boot_mode status
    fi
}
