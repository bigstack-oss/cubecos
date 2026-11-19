# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# Serving the web UIs on an FQDN (cubesys.fqdn, issue #340).
#
# cube-cos-api drives these: it installs the operator's certificate, sets cubesys.fqdn on every
# node (hex_config then rewrites each node's configuration on the public host and serves the
# certificate on the browser-facing listeners), and runs fqdn_cluster_apply once for what lives
# in the cluster rather than on a node. Resetting the FQDN runs the same path back to the VIP.
#
# The operator's certificate is kept apart from the appliance's own (/var/www/certs), which
# RabbitMQ, the SAML signing keys and every other internal client keep using.

FQDN_CERT_DIR=/etc/cube/certs
FQDN_CERT_PREV=/etc/cube/certs.prev
FQDN_FEDERATION_DIR=/etc/httpd/federation
FQDN_KEYCLOAK_METADATA=/etc/keycloak/saml-metadata.xml
FQDN_NOVA_PEM=/var/lib/nova/certs/server.pem
FQDN_K3S="/usr/local/bin/k3s kubectl"
FQDN_DASHBOARD_PORT=7443
FQDN_INGRESS_PORT=10443

_fqdn_err()
{
    echo "Error: $*" >&2
}

# cubesys.fqdn, empty when none is set
fqdn_get()
{
    source hex_tuning /etc/settings.txt cubesys.fqdn
    echo -n "$T_cubesys_fqdn"
}

# _fqdn_pem_split <file> <dir> <prefix>
#
# One file per certificate in <file>, named <dir>/<prefix>NN.pem in file order.
_fqdn_pem_split()
{
    awk -v d="$2" -v p="$3" '
        /-----BEGIN CERTIFICATE-----/ { n++ ; f = sprintf("%s/%s%02d.pem", d, p, n) }
        f { print > f }
        /-----END CERTIFICATE-----/ { close(f) ; f = "" }
    ' "$1"
}

_fqdn_is_self_signed()
{
    [ "$(openssl x509 -in "$1" -noout -subject_hash)" == "$(openssl x509 -in "$1" -noout -issuer_hash)" ] &&
        openssl verify -CAfile "$1" "$1" >/dev/null 2>&1
}

# _fqdn_cert_check <dir> <fqdn> <work>
#
# Checks the certificate set in <dir> -- server.cert (the certificate, optionally followed by
# its intermediates), server.key, ca.cert (the issuing CA: its root, optionally with the
# intermediates) -- and leaves in <work>:
#   served.pem  the certificate followed by its intermediates in issuing order, what the
#               listeners send; intermediates may come in either file
#   roots.pem   the root CA(s) from ca.cert, what clients on the node verify against
#   leaf.pem    the certificate alone
# With <fqdn>, the certificate must also cover that name.
#
# A browser rejects a chain it cannot complete, and Skyline, Rancher's agents and the ceph
# dashboard verify it on the node as well, so the whole chain is checked here, before any
# listener serves it, rather than discovered at the next login.
_fqdn_cert_check()
{
    local dir=$1 fqdn=$2 work=$3

    if [ ! -s "$dir/server.cert" ] ; then
        _fqdn_err "no certificate given"
        return 1
    fi
    if [ ! -s "$dir/server.key" ] ; then
        _fqdn_err "no private key given"
        return 1
    fi
    if [ ! -s "$dir/ca.cert" ] ; then
        _fqdn_err "no CA certificate given: the root CA that issued the certificate is required"
        return 1
    fi

    _fqdn_pem_split "$dir/server.cert" "$work" chain-
    _fqdn_pem_split "$dir/ca.cert" "$work" ca-
    if [ ! -f "$work/chain-01.pem" ] ; then
        _fqdn_err "the certificate is not a PEM certificate"
        return 1
    fi
    if ! ls "$work"/ca-*.pem >/dev/null 2>&1 ; then
        _fqdn_err "the CA certificate is not a PEM certificate"
        return 1
    fi
    cp -f "$work/chain-01.pem" "$work/leaf.pem"

    # the key: unencrypted, and the one the certificate was issued for
    if ! openssl pkey -in "$dir/server.key" -passin pass: -pubout -out "$work/key.pub" 2>/dev/null ; then
        _fqdn_err "the private key cannot be read; it must be an unencrypted PEM key"
        return 1
    fi
    openssl x509 -in "$work/leaf.pem" -noout -pubkey > "$work/leaf.pub"
    if ! cmp -s "$work/leaf.pub" "$work/key.pub" ; then
        _fqdn_err "the private key does not belong to the certificate"
        return 1
    fi

    if ! openssl x509 -in "$work/leaf.pem" -noout -checkend 0 >/dev/null ; then
        _fqdn_err "the certificate expired on $(openssl x509 -in "$work/leaf.pem" -noout -enddate | cut -d= -f2)"
        return 1
    fi
    local start=""
    start=$(date -d "$(openssl x509 -in "$work/leaf.pem" -noout -startdate | cut -d= -f2)" +%s 2>/dev/null)
    if [ -n "$start" ] && [ "$start" -gt "$(date +%s)" ] ; then
        _fqdn_err "the certificate is not valid before $(openssl x509 -in "$work/leaf.pem" -noout -startdate | cut -d= -f2)"
        return 1
    fi

    # roots come only from ca.cert; any other certificate, in either file, is an intermediate
    : > "$work/roots.pem"
    : > "$work/inter.pem"
    local c="" fp="" seen=" "
    for c in "$work"/ca-*.pem "$work"/chain-*.pem ; do
        [ "$c" != "$work/chain-01.pem" ] || continue
        fp=$(openssl x509 -in "$c" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
        if [ -z "$fp" ] ; then
            _fqdn_err "$(basename "$c") is not a readable certificate"
            return 1
        fi
        [[ "$seen" != *" $fp "* ]] || continue
        seen+="$fp "
        if _fqdn_is_self_signed "$c" ; then
            if [[ "$c" == "$work"/ca-* ]] ; then
                cat "$c" >> "$work/roots.pem"
            fi
        else
            cp -f "$c" "$work/inter-$(echo "$fp" | tr -d ':').pem"
            cat "$c" >> "$work/inter.pem"
        fi
    done
    if [ ! -s "$work/roots.pem" ] ; then
        _fqdn_err "the CA certificate holds no root CA (a self-signed certificate)"
        return 1
    fi

    # -untrusted only with intermediates: openssl refuses an empty file, which would reject a
    # certificate the root signed directly
    local out="" untrusted=()
    [ ! -s "$work/inter.pem" ] || untrusted=(-untrusted "$work/inter.pem")
    if ! out=$(openssl verify -CAfile "$work/roots.pem" "${untrusted[@]}" "$work/leaf.pem" 2>&1) ; then
        _fqdn_err "the certificate does not chain to the given CA" \
                  "($(echo "$out" | sed -n 's/^.*error [0-9]* at [0-9]* depth lookup: //p' | head -1)):" \
                  "include every intermediate CA, in the certificate or the CA file"
        return 1
    fi

    if [ -n "$fqdn" ] && ! openssl x509 -in "$work/leaf.pem" -noout -checkhost "$fqdn" | grep -q "does match" ; then
        _fqdn_err "the certificate does not cover $fqdn"
        return 1
    fi

    # the served chain: walk up from the certificate through its issuers
    cp -f "$work/leaf.pem" "$work/served.pem"
    local cur="$work/leaf.pem" next="" i=""
    for i in 1 2 3 4 5 6 7 8 ; do
        next=""
        for c in "$work"/inter-*.pem ; do
            [ -f "$c" ] || continue
            if [ "$(openssl x509 -in "$c" -noout -subject_hash)" == "$(openssl x509 -in "$cur" -noout -issuer_hash)" ] &&
               ! grep -qF -f <(sed -n 2p "$c") "$work/served.pem" ; then
                next=$c
                break
            fi
        done
        [ -n "$next" ] || break
        cat "$next" >> "$work/served.pem"
        cur=$next
    done

    return 0
}

# _fqdn_cert_json <certificate>
_fqdn_cert_json()
{
    local cert=$1
    local sans=""
    sans=$(openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null | tail -n +2 | tr ',' '\n' |
           sed -n 's/^[[:space:]]*DNS:\(.*\)$/\1/p' | jq -R . | jq -s -c .)
    jq -c -n \
        --arg subject "$(openssl x509 -in "$cert" -noout -subject -nameopt RFC2253 | sed 's/^subject=//')" \
        --arg issuer "$(openssl x509 -in "$cert" -noout -issuer -nameopt RFC2253 | sed 's/^issuer=//')" \
        --arg notBefore "$(date -u -d "$(openssl x509 -in "$cert" -noout -startdate | cut -d= -f2)" +%Y-%m-%dT%H:%M:%SZ)" \
        --arg notAfter "$(date -u -d "$(openssl x509 -in "$cert" -noout -enddate | cut -d= -f2)" +%Y-%m-%dT%H:%M:%SZ)" \
        --arg fingerprint "$(openssl x509 -in "$cert" -noout -fingerprint -sha256 | cut -d= -f2)" \
        --argjson dnsNames "${sans:-[]}" \
        '{subject: $subject, issuer: $issuer, dnsNames: $dnsNames, notBefore: $notBefore, notAfter: $notAfter, fingerprint: $fingerprint}'
}

# fqdn_cert_verify <dir> [fqdn]
#
# Checks the certificate set in <dir> (see _fqdn_cert_check) without installing it, and prints
# its summary as JSON. Errors go to stderr; non-zero when the set cannot be served.
fqdn_cert_verify()
{
    local dir=$1 fqdn=${2:-}
    local work=""
    work=$(mktemp -d /tmp/fqdn-cert.XXXXXX)

    if ! _fqdn_cert_check "$dir" "$fqdn" "$work" ; then
        rm -rf "$work"
        return 1
    fi

    _fqdn_cert_json "$work/leaf.pem"
    rm -rf "$work"
    return 0
}

# fqdn_cert_install <dir>
#
# Installs the certificate set in <dir> as the one the browser-facing listeners serve while
# cubesys.fqdn is set, here and on every other control node, and prints its summary. While an
# FQDN is set the certificate has to cover it. The previous certificate is kept in
# FQDN_CERT_PREV on this node. Nothing reloads here: fqdn_node_reload and fqdn_cluster_apply
# put a replacement in front of browsers when an FQDN is already set.
fqdn_cert_install()
{
    local dir=$1
    local fqdn=""
    fqdn=$(fqdn_get)
    local work=""
    work=$(mktemp -d /tmp/fqdn-cert.XXXXXX)

    if ! _fqdn_cert_check "$dir" "$fqdn" "$work" ; then
        rm -rf "$work"
        return 1
    fi

    local new=$FQDN_CERT_DIR.new
    rm -rf "$new"
    mkdir -p "$new"
    chmod 0755 "$new"
    cp -f "$work/served.pem" "$new/server.cert"
    cp -f "$work/roots.pem" "$new/ca.cert"
    (umask 077 ; openssl pkey -in "$dir/server.key" -out "$new/server.key" 2>/dev/null)
    (umask 077 ; cat "$new/server.cert" "$new/server.key" > "$new/server.pem")
    chmod 0644 "$new/server.cert" "$new/ca.cert"
    chmod 0600 "$new/server.key" "$new/server.pem"
    chown -R root:root "$new"

    if [ -d "$FQDN_CERT_DIR" ] ; then
        rm -rf "$FQDN_CERT_PREV"
        mv "$FQDN_CERT_DIR" "$FQDN_CERT_PREV"
    fi
    mv "$new" "$FQDN_CERT_DIR"

    # over ssh, as the appliance's own certificate is: the private key does not cross the
    # management network in an HTTP body
    if is_control_node && [ ${#CUBE_NODE_CONTROL_HOSTNAMES[@]} -gt 1 ] ; then
        if ! cubectl node rsync -r control $FQDN_CERT_DIR >/dev/null 2>&1 ; then
            _fqdn_err "the certificate was installed here but could not be copied to every control node"
            rm -rf "$work"
            return 1
        fi
    fi

    _fqdn_cert_json "$work/leaf.pem"
    rm -rf "$work"
    return 0
}

# fqdn_cert_show
#
# The installed certificate's summary as JSON, or {} when none is installed.
fqdn_cert_show()
{
    if [ -s "$FQDN_CERT_DIR/server.cert" ] ; then
        _fqdn_cert_json "$FQDN_CERT_DIR/server.cert"
    else
        echo -n "{}"
    fi
}

# fqdn_node_reload
#
# Put the installed certificate in front of browsers on this node, after it was replaced while
# an FQDN is set. A certificate change alone changes no setting, so no commit runs for it.
fqdn_node_reload()
{
    is_control_node || return 0
    [ "$(public_cert_dir)" == "$FQDN_CERT_DIR" ] || return 0

    local r=0
    systemctl reload haproxy || r=1
    systemctl reload httpd || r=1
    systemctl reload nginx || r=1

    # novncproxy serves a copy nova can read (config_nova.cpp)
    if [ -d "$(dirname $FQDN_NOVA_PEM)" ] && ! cmp -s "$FQDN_CERT_DIR/server.pem" $FQDN_NOVA_PEM ; then
        cp -f "$FQDN_CERT_DIR/server.pem" $FQDN_NOVA_PEM
        chown nova:nova $FQDN_NOVA_PEM
        chmod 600 $FQDN_NOVA_PEM
        if systemctl is-enabled --quiet openstack-nova-novncproxy 2>/dev/null ; then
            systemctl restart openstack-nova-novncproxy || r=1
        fi
    fi

    return $r
}

# _fqdn_keycloak_on <host>: Keycloak's chart and the IdP metadata every SP reads name <host>
_fqdn_keycloak_on()
{
    local host=$1
    local deployed=""
    deployed=$(helm --kubeconfig=/etc/rancher/k3s/k3s.yaml get values keycloak -n keycloak -o json 2>/dev/null |
               jq -r '.cubeController // empty')
    [ "$deployed" == "$host" ] &&
        grep -q "entityID=\"https://$host:$FQDN_INGRESS_PORT/auth/realms/master\"" $FQDN_KEYCLOAK_METADATA 2>/dev/null
}

_fqdn_step()
{
    echo "fqdn: $*"
}

# _fqdn_tf <module> <host> [keycloak]: apply one terraform module on <host>, failing loudly
# (the sdk wrappers that normally apply these ignore terraform's exit status)
_fqdn_tf()
{
    local module=$1 host=$2
    if [ "${3:-}" == "keycloak" ] ; then
        Quiet $TERRAFORM_CUBE apply -auto-approve -target=module.$module -var "cube_controller=$host" \
            "-var-file=$TERRAFORM_VAR_FILE_KEYCLOAK_ADMIN_PASSWORD"
    else
        Quiet $TERRAFORM_CUBE apply -auto-approve -target=module.$module -var "cube_controller=$host"
    fi
}

# _fqdn_k8s_secret_apply <namespace> <create secret args...>: replace a secret, or create it
# when there is none. Not apply: the appliance creates these secrets imperatively, and apply
# warns about the missing last-applied annotation on every one.
_fqdn_k8s_secret_apply()
{
    local ns=$1
    shift
    local yaml=""
    yaml=$($FQDN_K3S -n "$ns" create secret "$@" --dry-run=client -o yaml) || return 1
    echo "$yaml" | $FQDN_K3S -n "$ns" replace -f - >/dev/null 2>&1 ||
        echo "$yaml" | $FQDN_K3S -n "$ns" create -f - >/dev/null
}

# _fqdn_cluster_certs <cert dir>
#
# The browser-facing listeners that live in the cluster rather than on a node: the ceph
# dashboard (a mgr module) and the k3s ingress Keycloak and Rancher are reached on, whose CA
# Rancher hands to its agents.
_fqdn_cluster_certs()
{
    local certs=$1
    local ca=$certs/server.cert
    [ "$certs" != "$FQDN_CERT_DIR" ] || ca=$certs/ca.cert
    local r=0

    if $CEPH -s >/dev/null 2>&1 ; then
        if [ "$($CEPH config-key get mgr/dashboard/crt 2>/dev/null)" != "$(cat $certs/server.cert)" ] ; then
            _fqdn_step "ceph dashboard certificate"
            # the dashboard reads its certificate when the module starts
            if $CEPH dashboard set-ssl-certificate -i $certs/server.cert >/dev/null &&
               $CEPH dashboard set-ssl-certificate-key -i $certs/server.key >/dev/null ; then
                $CEPH mgr module disable dashboard && $CEPH mgr module enable dashboard || r=1
            else
                r=1
            fi
        fi
    fi

    _fqdn_step "ingress certificate"
    _fqdn_k8s_secret_apply ingress-nginx tls tls-private --cert=$certs/server.cert --key=$certs/server.key || r=1

    local cur=""
    cur=$($FQDN_K3S -n cattle-system get secret tls-ca -o jsonpath='{.data.cacerts\.pem}' 2>/dev/null | base64 -d 2>/dev/null)
    if [ "$cur" != "$(cat $ca)" ] ; then
        _fqdn_step "rancher CA"
        if _fqdn_k8s_secret_apply cattle-system generic tls-ca --from-file=cacerts.pem=$ca ; then
            # rancher reads its cacerts setting from the secret at start
            $FQDN_K3S -n cattle-system rollout restart deployment/rancher >/dev/null || r=1
        else
            r=1
        fi
    fi

    return $r
}

# fqdn_cluster_apply [cert]
#
# The part of an FQDN switch -- or of resetting it -- that lives in the cluster rather than on
# a node, run once, on a control node, after every node has committed cubesys.fqdn: Keycloak's
# hostname and the IdP metadata, keystone's trust in it, the SAML clients of keystone,
# cube-cos-api, the ceph dashboard and Rancher, Rancher's server URL, and the certificates of
# the ingress and the ceph dashboard. Each step is idempotent, so it is safe to re-run after a
# failure, and every step is tried: the output names the ones to look at.
#
# With "cert", only the certificates: a replacement installed while the FQDN stays.
fqdn_cluster_apply()
{
    local only=${1:-}
    local host="" sid="" fqdn="" certs=""
    host=$(public_host)
    sid=$(shared_ip)
    fqdn=$(fqdn_get)
    certs=$(public_cert_dir)
    local failed=()

    if ! is_control_node ; then
        _fqdn_err "fqdn_cluster_apply runs on a control node"
        return 1
    fi
    if [ -n "$fqdn" ] && [ "$certs" != "$FQDN_CERT_DIR" ] ; then
        _fqdn_err "cubesys.fqdn is $fqdn but no certificate is installed for it"
        return 1
    fi

    _fqdn_cluster_certs "$certs" || failed+=("certificates")
    if [ "$only" == "cert" ] ; then
        [ ${#failed[@]} -eq 0 ] || { _fqdn_err "failed: ${failed[*]}" ; return 1 ; }
        return 0
    fi

    # Keycloak follows PUBLIC_HOST in its own commit (config_keycloak.cpp), which re-installs
    # the chart and fetches the IdP metadata again when either still names another host
    _fqdn_step "keycloak on $host"
    if ! _fqdn_keycloak_on "$host" ; then
        $HEX_CFG install_keycloak >/dev/null 2>&1
    fi
    if ! _fqdn_keycloak_on "$host" ; then
        _fqdn_err "keycloak does not advertise $host yet; the SAML clients below follow it"
        failed+=("keycloak")
    fi
    cubectl node rsync -r control $FQDN_KEYCLOAK_METADATA >/dev/null 2>&1 || failed+=("idp metadata sync")

    _fqdn_step "keystone identity provider"
    local ids="--remote-id https://$sid:$FQDN_INGRESS_PORT/auth/realms/master"
    [ -z "$fqdn" ] || ids+=" --remote-id https://$fqdn:$FQDN_INGRESS_PORT/auth/realms/master"
    $OPENSTACK identity provider set $ids cube_idp >/dev/null || failed+=("keystone identity provider")

    # mellon's SP: generated once and handed to every control, so all of them sign with the
    # keypair Keycloak holds (#1216)
    _fqdn_step "keystone SAML SP"
    if ! grep -q "entityID=\"https://$host:5443/v3/mellon/metadata\"" $FQDN_FEDERATION_DIR/v3.xml 2>/dev/null ; then
        $HEX_SDK os_keystone_idp_config "$host" >/dev/null 2>&1
    fi
    if grep -q "entityID=\"https://$host:5443/v3/mellon/metadata\"" $FQDN_FEDERATION_DIR/v3.xml 2>/dev/null &&
       _fqdn_tf keycloak_keystone "$host" keycloak &&
       cubectl node rsync -r control $FQDN_FEDERATION_DIR >/dev/null 2>&1 &&
       cubectl node rsync -r control /etc/keycloak/keystone_sp_metadata.xml >/dev/null 2>&1 ; then
        cmd -c "systemctl reload httpd" >/dev/null 2>&1 || failed+=("httpd reload")
    else
        failed+=("keystone SAML SP")
    fi

    _fqdn_step "cube-cos-api SAML client"
    _fqdn_tf keycloak_api "$host" keycloak || failed+=("cube-cos-api SAML client")

    if $CEPH -s >/dev/null 2>&1 ; then
        _fqdn_step "ceph dashboard SSO"
        $CEPH dashboard set-grafana-api-url "https://$host/grafana" >/dev/null || failed+=("ceph dashboard grafana url")
        # the SP signs with the appliance's own key, as ceph_dashboard_idp_config sets it up;
        # its client is applied twice for the same reason that function does it twice
        if $CEPH dashboard sso setup saml2 "https://$host:$FQDN_DASHBOARD_PORT" $FQDN_KEYCLOAK_METADATA username \
               "https://$host:$FQDN_INGRESS_PORT/auth/realms/master" \
               /var/www/certs/server.cert /var/www/certs/server.key >/dev/null &&
           $CEPH dashboard sso enable saml2 >/dev/null ; then
            _fqdn_tf keycloak_ceph_dashboard "$host" keycloak
            _fqdn_tf keycloak_ceph_dashboard "$host" keycloak || failed+=("ceph dashboard SAML client")
        else
            failed+=("ceph dashboard SSO")
        fi
    fi

    _fqdn_step "rancher"
    local token=""
    token=$($TERRAFORM_CUBE state pull 2>/dev/null |
            jq -r '.resources[] | select(.type == "rancher2_bootstrap").instances[0].attributes.token // empty' 2>/dev/null)
    if [ -n "$token" ] &&
       $CURL -skf -X PUT -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
           -d "{\"value\": \"https://$host:$FQDN_INGRESS_PORT\"}" \
           "https://$sid:$FQDN_INGRESS_PORT/v3/settings/server-url" >/dev/null ; then
        _fqdn_tf rancher "$host" || failed+=("rancher auth config")
        _fqdn_tf keycloak_rancher "$host" keycloak || failed+=("rancher SAML client")
    else
        failed+=("rancher server url")
    fi

    if [ ${#failed[@]} -gt 0 ] ; then
        _fqdn_err "failed: ${failed[*]}"
        return 1
    fi

    return 0
}

# fqdn_status
#
# This node's view as JSON: the FQDN, the host browsers are sent to, the installed certificate,
# and whether this node serves it.
fqdn_status()
{
    jq -c -n \
        --arg fqdn "$(fqdn_get)" \
        --arg publicHost "$(public_host)" \
        --arg servedFrom "$(public_cert_dir)" \
        --argjson certificate "$(fqdn_cert_show)" \
        '{fqdn: $fqdn, publicHost: $publicHost, servedFrom: $servedFrom, certificate: $certificate}'
}
