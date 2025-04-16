# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

api_idp_config()
{
    local SHARED_ID=$1
    $TERRAFORM_CUBE apply -auto-approve -target=module.keycloak_api -var cube_controller=$SHARED_ID >/dev/null
}
