# HEX SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# Usage: $PROG appliance_shutdown [<delay_secs>]
eval "`declare -f appliance_shutdown | sed '1s/.*/_&/'`"
appliance_shutdown()
{
    if $CEPH -s >/dev/null ; then
        timeout 10 umount $CEPHFS_STORE_DIR
        Quiet -n $HEX_SDK ceph_osd_compact
        if is_control_node ; then
            systemctl stop nfs-ganesha
            Quiet -n $CEPH mds fail $HOSTNAME
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
        Quiet -n $HEX_SDK ceph_osd_compact
        if is_control_node ; then
            systemctl stop nfs-ganesha
            Quiet -n $CEPH mds fail $HOSTNAME
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
        Quiet -n $HEX_SDK ceph_osd_compact
        if is_control_node ; then
            systemctl stop nfs-ganesha
            Quiet -n $CEPH mds fail $HOSTNAME
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
        Quiet -n $HEX_SDK ceph_osd_compact
        if is_control_node ; then
            systemctl stop nfs-ganesha
            Quiet -n $CEPH mds fail $HOSTNAME
        fi
    fi
    _${FUNCNAME[0]} $@
}

eval "`declare -f banner_login | sed '1s/.*/_&/'`"
banner_login()
{
    local space=22
    _${FUNCNAME[0]}
    local role=$(cat $SETTINGS_TXT | grep "cubesys.role" | cut -d'=' -f2 | xargs)
    local srv_st="services ready"
    [ -e /run/cube_commit_done ] || srv_st="services n/a"
    printf "%${space}s | %s\n\n" "$role" "$srv_st"
    echo "----------"
    if grep -q '[.]controller =' $SETTINGS_TXT ; then
        printf "%${space}s" "$(grep '[.]controller =' $SETTINGS_TXT | cut -d'=' -f2 | xargs)"
        if grep -q 'controller[.]ip' $SETTINGS_TXT ; then
            printf " | %s\n\n" "$(grep 'controller[.]ip' $SETTINGS_TXT | cut -d'=' -f2 | xargs)"
        else
            printf " | %s\n\n" "$($HEX_SDK -f json health_vip_report | jq -r .description)"
        fi
    fi
    printf "%${space}s x %s\n" "${#CUBE_NODE_CONTROL_HOSTNAMES[@]}" "control"
    printf "%${space}s x %s\n" "${#CUBE_NODE_COMPUTE_HOSTNAMES[@]}" "compute"
    printf "%${space}s x %s\n" "${#CUBE_NODE_STORAGE_HOSTNAMES[@]}" "storage"
}
