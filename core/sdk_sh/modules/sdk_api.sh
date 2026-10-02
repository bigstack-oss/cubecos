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
    Quiet -n $TERRAFORM_CUBE apply \
        -auto-approve -target=module.keycloak_lmi \
        -var "cube_controller=${shared_id}" \
        "-var-file=${TERRAFORM_VAR_FILE_KEYCLOAK_ADMIN_PASSWORD}"
    # add API configurations to Keycloak
    Quiet -n $TERRAFORM_CUBE apply \
        -auto-approve -target=module.keycloak_api \
        -var "cube_controller=${shared_id}" \
        "-var-file=${TERRAFORM_VAR_FILE_KEYCLOAK_ADMIN_PASSWORD}"
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

# cube-cos-api's own keystone user and EC2 credential, so it stops sharing admin's.
#
# This lives with the API rather than under os_ because the credential shape is the
# API's, not a general one: cube-cos-api treats its "accessKey" setting as a keystone
# user NAME and signs with an access key equal to that name, so the credential written
# here must use the user name as its access key. A generic S3-user helper would take an
# access key and a secret independently.
#
# The shared credential is genuinely contested. cube-cos-api mints one whose access key
# is literally the username -- its accessKey setting is a keystone user name, defaulting
# to "admin" -- while sdk_health and cube_cluster_start_cluster list admin's credentials,
# cache the first in /run/ec2.key and delete/recreate on an empty read. So
# `ec2 credentials delete admin` removes precisely the credential the API created, and
# whichever side runs next silently adopts or destroys the other's key. Issue #703.
#
# Access to the shared "log" bucket survives the split because rgw runs with
# `rgw keystone implicit tenants = false`: the S3 owner is the keystone PROJECT, not the
# user, and "log" is owned by the admin project. Any user holding an rgw-accepted role
# on that project therefore authenticates as that same S3 owner, so no bucket policy or
# ACL is needed -- verified by `radosgw-admin bucket stats --bucket=log`, whose owner is
# the admin project id.
#
# Idempotent: safe to run on every commit.
api_s3_user_setup()
{
    local user=$1
    local secret=$2
    local domain=${3:-default}
    local project=${4:-admin}

    if [ "x$user" = "x" -o "x$secret" = "x" ] ; then
        log_error "api_s3_user_setup: usage: api_s3_user_setup <user> <secret> [domain] [project]"
        return 1
    fi

    if ! $OPENSTACK user show $user >/dev/null 2>&1 ; then
        log_info "api_s3_user_setup: creating keystone user $user"
        # No password: the EC2 credential is the only way this identity is ever used,
        # so there is nothing to gain from it being able to log in.
        $OPENSTACK user create --domain $domain $user >/dev/null 2>&1
    fi
    if ! $OPENSTACK user show $user >/dev/null 2>&1 ; then
        log_error "api_s3_user_setup: keystone user $user missing after create"
        return 1
    fi

    # "member" rather than "admin": rgw keystone accepted roles includes it, and it is
    # the project mapping above -- not the role -- that grants the bucket access.
    $OPENSTACK role add --project $project --user $user member >/dev/null 2>&1
    if ! $OPENSTACK role assignment list --user $user --project $project --names -f value -c Role 2>/dev/null | grep -q . ; then
        log_error "api_s3_user_setup: $user has no role on project $project"
        return 1
    fi

    # Own the EC2 credential here rather than leaving it to cube-cos-api. The API does
    # create it on startup, but treats an HTTP 409 as success -- so the first time the
    # configured secret changes (a new seed, or the api.s3.secret tuning) keystone keeps
    # the old secret while the API signs with the new one, and every S3 request is denied
    # with nothing in either log saying why. Reconciling here makes the API's own create
    # a harmless no-op and the pair self-healing.
    #
    # The access key is the user name, which is what cube-cos-api derives from its
    # accessKey setting -- the two must agree or the API signs with a key keystone has
    # never heard of.
    local id cur
    read -r id cur <<< "$($OPENSTACK credential list --user $user --type ec2 -f json 2>/dev/null \
        | jq -r --arg a "$user" '.[] | select((.Data|fromjson).access == $a)
                                     | "\(.ID) \((.Data|fromjson).secret)"' | head -1)"
    if [ "x$id" != "x" -a "x$cur" = "x$secret" ] ; then
        return 0
    fi
    if [ "x$id" != "x" ] ; then
        log_info "api_s3_user_setup: rotating stale ec2 credential for $user"
        $OPENSTACK credential delete $id >/dev/null 2>&1
    fi
    log_info "api_s3_user_setup: creating ec2 credential for $user"
    $OPENSTACK credential create --type ec2 --project $project $user \
        "{\"access\": \"$user\", \"secret\": \"$secret\"}" >/dev/null 2>&1
    if ! $OPENSTACK credential list --user $user --type ec2 -f json 2>/dev/null \
        | jq -e --arg a "$user" --arg s "$secret" \
            'any(.[]; (.Data|fromjson).access == $a and (.Data|fromjson).secret == $s)' >/dev/null 2>&1 ; then
        log_error "api_s3_user_setup: ec2 credential for $user is not in place"
        return 1
    fi

    return 0
}
