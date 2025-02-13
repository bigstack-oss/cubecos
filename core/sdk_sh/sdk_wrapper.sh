# HEX SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ]; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# Usage: $PROG appliance_shutdown [<delay_secs>]
eval "`declare -f appliance_shutdown | sed '1s/.*/_&/'`"
appliance_shutdown()
{
    if $CEPH -s >/dev/null ; then
        timeout 10 umount $CEPHFS_STORE_DIR
        Quiet ceph_osd_compact || true
        if is_control_node ; then
            systemctl stop nfs-ganesha
            Quiet $CEPH mds fail $HOSTNAME || true
        fi
    fi
    _${FUNCNAME[0]} $@
}

# Usage: $PROG appliance_reboot [<delay_secs>]
eval "`declare -f appliance_reboot | sed '1s/.*/_&/'`"
appliance_reboot()
{
    if $CEPH -s >/dev/null ; then
        timeout 10 umount $CEPHFS_STORE_DIR
        Quiet ceph_osd_compact || true
        if is_control_node ; then
            systemctl stop nfs-ganesha
            Quiet $CEPH mds fail $HOSTNAME || true
        fi
    fi
    _${FUNCNAME[0]} $@
}

# Usage: $PROG swap_active_firmware [<delay_secs>]
eval "`declare -f firmware_swap_active | sed '1s/.*/_&/'`"
firmware_swap_active()
{
    if $CEPH -s >/dev/null ; then
        timeout 10 umount $CEPHFS_STORE_DIR
        Quiet ceph_osd_compact || true
        if is_control_node ; then
            systemctl stop nfs-ganesha
            Quiet $CEPH mds fail $HOSTNAME || true
        fi
    fi
    _${FUNCNAME[0]} $@
}

# Usage: $PROG firmware_backup [<delay_secs>]
eval "`declare -f firmware_backup | sed '1s/.*/_&/'`"
firmware_backup()
{
    if $CEPH -s >/dev/null ; then
        timeout 10 umount $CEPHFS_STORE_DIR
        Quiet ceph_osd_compact || true
        if is_control_node ; then
            systemctl stop nfs-ganesha
            Quiet $CEPH mds fail $HOSTNAME || true
        fi
    fi
    _${FUNCNAME[0]} $@
}

eval "`declare -f banner_login | sed '1s/.*/_&/'`"
banner_login()
{
    local SPACE=22
    _${FUNCNAME[0]}
    local ROLE=$(cat /etc/settings.txt | grep "cubesys.role" | cut -d'=' -f2 | xargs)
    local SRV_ST="services ready"
    [ -e /run/cube_commit_done ] || SRV_ST="services n/a"
    printf "%${SPACE}s | %s\n\n" "$ROLE" "$SRV_ST"
    echo "----------"
    if grep -q '[.]controller =' /etc/settings.txt; then
        printf "%${SPACE}s" "$(grep '[.]controller =' /etc/settings.txt | cut -d'=' -f2 | xargs)"
        if grep -q 'controller[.]ip' /etc/settings.txt; then
            printf " | %s\n\n" "$(grep 'controller[.]ip' /etc/settings.txt | cut -d'=' -f2 | xargs)"
        else
            printf " | %s\n\n" "$(health_vip_report 2>/dev/null)"
        fi
    fi
    printf "%${SPACE}s x %s\n" "$(cubectl node list -r control | wc -l)" "control"
    printf "%${SPACE}s x %s\n" "$(cubectl node list -r compute | wc -l)" "compute"
    printf "%${SPACE}s x %s\n" "$(cubectl node list -r storage | wc -l)" "storage"
}
