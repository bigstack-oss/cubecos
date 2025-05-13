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
