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

# Call cube-cos-api as this node (node token). $1 method, $2 path under the
# datacenter, $3 JSON body, $4 curl -m seconds, $5 address (default: this node,
# not the VIP, whose 1m haproxy timeout cuts long calls). Prints the HTTP status
# (000 when unreachable), then the body.
_api_request()
{
    local method="$1" path="$2" body="${3:-}" max="${4:-60}" addr="${5:-}"
    source hex_tuning /etc/settings.txt cubesys.controller
    [ -n "$addr" ] || addr="$(mgmt_ip)"

    local args=(-k -s -m "$max" -X "$method" -w '\n%{http_code}'
        -H "Node: $HOSTNAME"
        -H "Authorization: Bearer $(cat /var/run/cube-cos-api/node_token 2>/dev/null)")
    if [ -n "$body" ] ; then
        args+=(-H "Content-Type: application/json" --data-binary "$body")
    fi

    local out=""
    out="$(curl "${args[@]}" "http://${addr}:8082/api/v1/datacenters/${T_cubesys_controller}/${path}" 2>/dev/null)"
    local code="${out##*$'\n'}"
    [[ "$code" =~ ^[0-9]{3}$ ]] || code="000"
    echo "$code"
    [[ "$out" == *$'\n'* ]] && echo "${out%$'\n'*}"
    return 0
}

# the msg of a cube-cos-api answer; $1 status, $2 body
_api_msg()
{
    local msg=""
    msg="$(echo "$2" | jq -r '.msg // empty' 2>/dev/null)"
    if [ -n "$msg" ] ; then
        echo "$msg"
    elif [ "$1" == "000" ] ; then
        echo "cube-cos-api did not answer"
    else
        echo "cube-cos-api answered HTTP $1"
    fi
}

_api_call()
{
    local r="" code=""
    r="$(_api_request "$@")"
    code="${r%%$'\n'*}"
    [[ "$r" == *$'\n'* ]] && echo "${r#*$'\n'}"
    [[ "$code" == 2?? ]]
}

# $1 path, $2 JSON body, $3 max seconds. Print the body; 0 for a 2xx answer.
api_post() { _api_call POST "$1" "${2:-}" "${3:-60}" ; }
api_patch() { _api_call PATCH "$1" "${2:-}" "${3:-60}" ; }
# $1 path, $2 max seconds
api_delete() { _api_call DELETE "$1" "" "${2:-60}" ; }
api_get() { _api_call GET "$1" "" "${2:-60}" ; }

_api_uri() { jq -rn --arg s "$1" '$s | @uri' ; }

_api_storage_err()
{
    jq -c -n --arg message "$1" '{message: $message}' >&2
}

# Create or update an external storage through cube-cos-api, which applies it
# on every control (#2098), then wait until its backend is up. Input and output
# as cinder_put_storage.
api_storage_put()
{
    local input="${1:-""}"
    local name=""
    name="$(echo "$input" | jq -r '.name // empty' 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    name="${name//./-}"
    if [ -z "$name" ] ; then
        _api_storage_err "field name should not be blank"
        return 1
    fi

    local r="" code="" body=""
    r="$(_api_request POST integrations/storages "$input" 60)"
    code="${r%%$'\n'*}"
    if [ "$code" == "409" ] ; then
        r="$(_api_request PATCH "integrations/storages/$(_api_uri "$name")" "$input" 60)"
        code="${r%%$'\n'*}"
    fi
    body="${r#*$'\n'}"
    if [[ "$code" != 2?? ]] ; then
        _api_storage_err "storage ${name}: $(_api_msg "$code" "$body")"
        return 1
    fi

    local timeout="${API_STORAGE_WAIT:-300}"
    local pending=""
    pending="$($HEX_SDK cinder_wait_for_backends_ready "${name}@${name}" "$timeout")"
    if [ $? -ne 0 ] || [ -n "$pending" ] ; then
        _api_storage_err "storage ${name} was applied, but backend ${pending:-${name}@${name}} is not up after ${timeout}s"
        return 1
    fi

    jq -c -n --arg message "storage ${name} set" '{message: $message}'
}

# Delete an external storage through cube-cos-api, then wait until no control
# lists it. Input and output as cinder_delete_storage.
api_storage_delete()
{
    local input="${1:-""}"
    local name=""
    name="$(echo "$input" | jq -r '.name // empty' 2>/dev/null)"
    if [ -z "$name" ] ; then
        _api_storage_err "field name should not be blank"
        return 1
    fi

    # the API answers before any control acts, so refuse what each would
    if $HEX_SDK cinder_is_volume_type_in_use "$name" ; then
        _api_storage_err "volume type ${name} is still in use"
        return 1
    fi

    local r="" code=""
    r="$(_api_request DELETE "integrations/storages/$(_api_uri "$name")" "" 60)"
    code="${r%%$'\n'*}"
    if [[ "$code" != 2?? ]] ; then
        _api_storage_err "storage ${name}: $(_api_msg "$code" "${r#*$'\n'}")"
        return 1
    fi

    local left=""
    left="$(api_storage_wait_deleted "$name" "${API_STORAGE_WAIT:-300}")"
    if [ $? -ne 0 ] ; then
        _api_storage_err "storage ${name} is still configured on: ${left}"
        return 1
    fi

    # the API stops listing it before cinder-volume drops the backend
    local backend="${name//./-}@${name//./-}"
    left="$($HEX_SDK cinder_wait_for_backends_gone "$backend" "${API_STORAGE_WAIT:-300}")"
    if [ $? -ne 0 ] ; then
        _api_storage_err "storage ${name} was deleted, but backend ${backend} is still served after ${API_STORAGE_WAIT:-300}s"
        return 1
    fi

    jq -c -n --arg message "storage ${name} deleted" '{message: $message}'
}

# Wait up to $2 seconds until every control's cube-cos-api answers 404 for
# storage $1. Prints the controls that still list it, or could not be asked.
api_storage_wait_deleted()
{
    local name="$1" timeout="${2:-300}"
    local deadline=$((SECONDS + timeout))
    local path="integrations/storages/$(_api_uri "$name")"
    local addrs=($(echo "${CUBE_NODE_CONTROL_JSON:-[]}" | jq -r '.[].ip.management // empty' 2>/dev/null | sort -u))
    [ "${#addrs[@]}" -gt 0 ] || addrs=("$(mgmt_ip)")

    local left="" addr="" code=""
    while : ; do
        left=""
        for addr in "${addrs[@]}" ; do
            code="$(_api_request GET "$path" "" 10 "$addr" | head -n 1)"
            [ "$code" == "404" ] && continue
            [ "$code" == "000" ] && left+="${left:+, }${addr} (not answering)" || left+="${left:+, }${addr}"
        done
        if [ -z "$left" ] || [ $SECONDS -ge $deadline ] ; then
            break
        fi
        sleep 3
    done

    echo -n "$left"
    [ -z "$left" ]
}

# Create (or complete) device tier $1 on OSDs $2... through cube-cos-api: the
# Ceph part runs once, the registry and Cinder apply on every control
# (#2098). Then wait until its backend is up.
api_storage_tier_create()
{
    local tier="$1"
    shift

    local body="" r="" code="" resp=""
    body="$(jq -c -n --arg n "$tier" '{name: $n, osdIds: $ARGS.positional}' --args "$@")"
    r="$(_api_request POST integrations/storages/tiers "$body" 1800)"
    code="${r%%$'\n'*}"
    resp="${r#*$'\n'}"
    echo "$resp" | jq -r '.data.output // empty' 2>/dev/null
    if [[ "$code" != 2?? ]] ; then
        echo "Error: $(_api_msg "$code" "$resp")" >&2
        return 1
    fi

    local timeout="${API_STORAGE_WAIT:-300}"
    local pending=""
    pending="$($HEX_SDK cinder_wait_for_backends_ready "cube@${tier}" "$timeout")"
    if [ $? -ne 0 ] || [ -n "$pending" ] ; then
        echo "Error: device tier ${tier} was created, but its Cinder backend ${pending:-cube@${tier}} is not up after ${timeout}s" >&2
        return 1
    fi

    return 0
}

# Delete device tier $1 through cube-cos-api: every control unregisters it
# before the Ceph teardown runs once.
api_storage_tier_delete()
{
    local tier="$1"
    local r="" code="" resp=""
    r="$(_api_request DELETE "integrations/storages/tiers/$(_api_uri "$tier")" "" 1800)"
    code="${r%%$'\n'*}"
    resp="${r#*$'\n'}"
    echo "$resp" | jq -r '.data.output // empty' 2>/dev/null
    if [[ "$code" != 2?? ]] ; then
        echo "Error: $(_api_msg "$code" "$resp")" >&2
        return 1
    fi

    return 0
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
