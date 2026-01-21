# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

_os_cinder_get_volume_backend_pool_by_volume_type()
{
    # for internal use only, not properly formatted into JSON
    # input: _os_cinder_get_volume_backend_by_volume_type <volume_type>
    # output: <pool1>\n<pool2>
    local volume_type="${1:-"CubeStorage"}"

    local exec_output=""
    local exec_error=""

    local volume_backend=""
    if ! _hex_function exec_output exec_error $OPENSTACK volume type show "$volume_type" -c properties -f json ; then
        return 1
    fi
    if ! _hex_function exec_output exec_error jq -r ".properties.volume_backend_name" <(printf "%s" "$exec_output") ; then
        return 1
    fi
    volume_backend="$exec_output"
    if [ -z "$volume_backend" ] ; then
        volume_backend="ceph"
    fi

    if ! _hex_function exec_output exec_error $OPENSTACK volume backend pool list -c Name -f json ; then
        return 1
    fi
    if ! _hex_function exec_output exec_error jq -r ".[] | select(.Name | test(\"@${volume_backend}#\")) | .Name" <(printf "%s" "$exec_output") ; then
        return 1
    fi

    echo -n "$exec_output"
}

os_cinder_get_volume_backend_pool_by_volume_type()
{
    # input: os_cinder_get_volume_backend_pool_by_volume_type <volume_type>
    # output: [
    #   <pool1>,
    #   <pool2>
    # ]
    local volume_type="${1:-"CubeStorage"}"

    local exec_output=""
    local exec_error=""

    local volume_backend_pool="[]"
    if ! _hex_function exec_output exec_error _os_cinder_get_volume_backend_pool_by_volume_type "$volume_type" ; then
        echo -n "$volume_backend_pool"
        return 1
    fi

    local pool=""
    while read -r pool ; do
        volume_backend_pool="$(jq -c \
            --arg pool "$pool" \
            '. += [$pool]' \
            <(printf "%s" "$volume_backend_pool"))"
    done <<< "$exec_output"
    echo -n "$volume_backend_pool"
}

os_cinder_get_volume_backend_host_by_volume_type()
{
    # input: os_cinder_get_volume_backend_host_by_volume_type <volume_type>
    # output: [
    #   <host1>,
    #   <host2>
    # ]
    local volume_type="${1:-"CubeStorage"}"

    local exec_output=""
    local exec_error=""

    local volume_backend_host="[]"
    if ! _hex_function exec_output exec_error _os_cinder_get_volume_backend_pool_by_volume_type "$volume_type" ; then
        echo -n "$volume_backend_host"
        return 1
    fi

    local pool=""
    local host=""
    while read -r pool ; do
        host="$(echo "$pool" | cut -d "@" -f1)"
        volume_backend_host="$(jq -c \
            --arg host "$host" \
            '. += [$host]' \
            <(printf "%s" "$volume_backend_host"))"
    done <<< "$exec_output"
    echo -n "$volume_backend_host"
}
