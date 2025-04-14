# HEX SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# Usage: $PROG firmware_list
firmware_list()
{
    Debug "Listing firmware"
    if [ ! -f /boot/grub2/grub.cfg ] ; then
        Error "Firmware listing not found"
    fi
    source hex_tuning $SETTINGS_SYS sys.vendor
    /bin/grep $T_sys_vendor_name'_' /boot/grub2/grub.cfg 2>/dev/null | /usr/bin/head -2 | /usr/bin/awk '{print $2}' | /usr/bin/tr -d "\'"
}

# Usage: $PROG firmware_get_active
firmware_get_active()
{
    Debug "Getting active firmware"
    if [ ! -f /usr/sbin/grub-get-default ] ; then
        Error "Unable to get active firmware information"
    fi
    local active=$(/usr/sbin/grub-get-default 2>/dev/null)
    echo -n $active
}

# Usage: $PROG swap_active_firmware [<delay_secs>]
firmware_swap_active()
{
    local delay=${1:-0}

    Debug "Swapping active firmware"
    local current=$(firmware_get_active)
    local next=0

    if (( "$current" == 1 )) ; then
        next=2
    else
        next=1
    fi

    /usr/sbin/grub-set-default $next

    echo "System is rebooting for partition $next in $delay seconds"
    if (( "$delay" > 0 )) ; then
        $HEX_CFG reboot $delay
    else
        $HEX_CFG reboot
    fi
}

# Usage: $PROG firmware_backup [<delay_secs>]
firmware_backup()
{
    local delay=${1:-0}

    Debug "Back up active firmware"
    local current=$(firmware_get_active)
    local backup=$((current + 2))

    /usr/sbin/grub-set-default $backup

    echo "System is rebooting for backup partition $current in $delay seconds"
    if (( "$delay" > 0 )) ; then
        $HEX_CFG reboot $delay
    else
        $HEX_CFG reboot
    fi
}

# Usage: $PROG firmware_get_comment <partition>
firmware_get_comment()
{
    local part=$1

    Debug "Getting firmware comment"
    (( part < 1 || part > 2)) && Error "Invalid firmware index specified: $part"

    /bin/cat /boot/grub2/comment$part
}

# Usage: $PROG firmware_set_comment <partition> <comment|comment-file>
firmware_set_comment()
{
    local part=$1
    local comment=${2:-""}

    Debug "Setting firmware comment"
    (( part < 1 || part > 2)) && Error "Invalid firmware index specified: $part"

    if [ -f "$comment" ] ; then
        cp $comment /boot/grub2/comment$part
    else
        echo -n $comment > /boot/grub2/comment$part
    fi
}

# Usage: $PROG firmware_get_info <partition>
firmware_get_info()
{
    local part=$1

    Debug "Getting firmware info"
    (( part < 1 || part > 2)) && Error "Invalid firmware index specified: $part"

    /bin/cat /boot/grub2/info$part
}
