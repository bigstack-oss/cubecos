# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

lmi_idp_config()
{
    local shared_id=$1
    Quiet -n terraform-cube.sh apply -auto-approve -target=module.keycloak_lmi -var cube_controller=$shared_id
}
