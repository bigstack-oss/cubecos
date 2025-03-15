# HEX SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

preset_interface_set()
{
    local name=$1
    local cidr=$2

    ip link set $name up
    ifconfig $name $cidr
}

preset_bond_set()
{
    local name=$1
    local slaves=$2
    local cidr=$3

    UpdateBondingInterface $name fast layer3+4
    for s in ${slaves//,/ } ; do
        AddBondingSlave $name $s
    done

    if [ -n "$cidr" ] ; then
        ifconfig $name $cidr
    fi
}

preset_vlan_set()
{
    local name=$1
    local vid=$2
    local cidr=$3

    UpdateVlanInterface $name $vid
    ifconfig $name.$vid $cidr
}

preset_interterface_clearall()
{
    for name in $(ls -1 /proc/net/vlan/ | grep -v '^config$') ; do
        preset_interterface_clear vlan $name
    done
    for name in $(cat /sys/class/net/bonding_masters) ; do
        preset_interterface_clear bond $name
    done
    for name in $($HEX_SDK -v DumpInterface | awk '{print $1}' | egrep -v '^Dev$|^-+$') ; do
        preset_interterface_clear eth $name
    done
}

preset_interterface_clear()
{
    local type=$1
    local name=$2

    ifconfig $name 0.0.0.0
    if [ "$type" == "bond" ] ; then
        ClearBondingIf $name
    elif [ "$type" == "vlan" ] ; then
        ClearVlanConfig $name
    else
        ip link set $name down
    fi
}

preset_interface_show()
{
    local name=$1

    if [ -z "$name" -o "$name" == "all" ] ; then
        DumpInterface 0
    else
        DumpInterface 0 | grep $name
    fi
}

preset_datetime_show()
{
    date "+%Y-%m-%d %H:%M:%S"
}

preset_ping()
{
    local ip=$1

    echo -n "Ping $ip ... "
    ping -c 1 -w 1 $ip >/dev/null && echo "OK" || echo "FAILED"
}
