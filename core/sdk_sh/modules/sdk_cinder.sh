# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

_is_all_true()
{
    local lines="${1:-""}"

    while read -r line; do
        if [ -z "$line" ]; then
            continue
        fi

        if [[ "$line" != "true" ]] ; then
            return 1
        fi
    done <<< "$lines"

    return 0
}

_are_services_up()
{
    local storage_backends="${1:-""}"

    local status="$(openstack volume service list -c Binary -c Host -c State -f json)"
    echo "$status" | jq "." > /dev/null 2>&1
    if [[ "$?" != "0" ]] ; then
        # the status is not a valid JSON string
        return 1
    fi

    _is_all_true "$(echo "$status" | jq -r ".[] | select(.Binary == \"cinder-scheduler\") | .State | test(\"up\")")"
    local isSchedulerUp="$?"
    if [[ "$isSchedulerUp" != "0" ]] ; then
        # cinder-scheduler is not up
        return 2
    fi

    _is_all_true "$(echo "$status" | jq -r ".[] | select(.Binary == \"cinder-backup\") | .State | test(\"up\")")"
    local isBackupUp="$?"
    if [[ "$isBackupUp" != "0" ]] ; then
        # cinder-backup is not up
        return 3
    fi

    local isVolumeUp="0"
    if [ ! -z "$storage_backends" ] ; then
        while read -r backend ; do
            _is_all_true "$(echo "$status" | jq -r ".[] | select(.Binary == \"cinder-volume\" and .Host == \"${backend//\"/}\") | .State | test(\"up\")")"
            isVolumeUp="$?"

            if [[ "$isVolumeUp" != "0" ]] ; then
                # cinder-volume is not up for this storage backend
                return 4
            fi
        done <<< "$(echo "$storage_backends" | tr ',' '\n')"
    else
        _is_all_true "$(echo "$status" | jq -r ".[] | select(.Binary == \"cinder-volume\") | .State | test(\"up\")")"
        isVolumeUp="$?"

        if [[ "$isVolumeUp" != "0" ]] ; then
            # cinder-volume is not up for all storage backends
            return 4
        fi
    fi

    return 0
}

cinder_wait_for_services_up()
{
    local storage_backends="${1:-""}"
    local timeout="${2:-10}"

    local i=0
    while [ $i -lt $timeout ] ; do
        if _are_services_up "$storage_backends" ; then
            break
        else
            sleep 1
        fi
        i=$(expr $i + 1)
    done
    [ $i -lt $timeout ]
}
