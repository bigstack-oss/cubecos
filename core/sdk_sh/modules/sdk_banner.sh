# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

banner_login()
{
    echo "Bigstack, Co. Cloud Platform" && echo
    local fwinfo=$( ( $HEX_SDK firmware_list | sed -n $(grub-get-default)p ) 2>/dev/null )
    if [ -n "$fwinfo" ] ; then
        local platform=$(echo $fwinfo | cut -d'_' -f1)
        local version=$(echo $fwinfo | cut -d'_' -f2)
        local built_time=$(echo $fwinfo | cut -d'_' -f3)
        local build=$(echo $fwinfo | cut -d'_' -f4)
        echo "$platform $version (Build $built_time $build)" && echo
    fi
    local cpu_cnt=$(cat /proc/cpuinfo | grep "physical id" | sort | uniq | wc -l)
    local cpu_inf=$(cat /proc/cpuinfo | grep "model name" | sort | uniq | cut -d':' -f2 | xargs)
    local mem_kb=$(cat /proc/meminfo | grep MemTotal | cut -d':' -f2 | xargs | cut -d' ' -f1)
    local mem_gb=$(echo "$mem_kb / 1024 / 1024" | bc)
    echo "$cpu_cnt x $cpu_inf"
    echo "$mem_gb GB memory" && echo
    license_show | grep state | sed 's/state: //' && echo
    local ipaddr=$(cat /etc/hosts | grep "$HOSTNAME$" | awk '{print $1}')
    [ -n "$ipaddr" ] || ipaddr=$(ip addr list | awk '/ global /{print $2}' | head -1)
    printf "%${SPACE}s | %s\n" "$HOSTNAME" "${ipaddr:-IP n/a}"
}

banner_login_greeting()
{
    source hex_tuning /etc/settings.txt appliance.login.greeting
    if [ -n "$T_appliance_login_greeting" ] ; then
        echo $T_appliance_login_greeting
    fi
}
