# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

api_idp_config()
{
    local shared_id=$1
    # migrate LMI configurations on Keycloak
    Quiet -n $TERRAFORM_CUBE apply -auto-approve -target=module.keycloak_lmi -var cube_controller=$shared_id
    # add API configurations to Keycloak
    Quiet -n $TERRAFORM_CUBE apply -auto-approve -target=module.keycloak_api -var cube_controller=$shared_id
}

_api()
{
    local endpoint_tmp=$(echo ${1:-BADENDPOINT} | sed "s/^api_get_//")
    local endpoint="${endpoint_tmp/_//}"

    source hex_tuning /etc/settings.txt cubesys.controller
    curl -k -X GET https://$(hex_sdk shared_ip)/api/v1/datacenters/${T_cubesys_controller}/${endpoint} -H "Node: $HOSTNAME" -H "Authorization: Bearer $(cat /var/run/cube-cos-api/node_token)" 2>/dev/null
}

api_get_images_materials()
{
    _api ${FUNCNAME[0]}
}
