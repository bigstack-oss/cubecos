# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

glance_lift_quota_for_volume_image()
{
    local service_project_id="$($OPENSTACK project show --domain default service -c id -f value)"
    $OPENSTACK quota set --gigabytes -1 "$service_project_id"
    $OPENSTACK quota set --volumes -1 "$service_project_id"
}
