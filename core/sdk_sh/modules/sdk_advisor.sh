# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# Node-side helpers for the Cube AI Advisor agent (ADR 0003).
#
# Releases are signed; the key and the check both live in hex_config, not here,
# because root can edit this file. The manifest is in sha256sum's own format, so
# a customer can repeat the check with openssl and sha256sum.

ADVISOR_TRUST_ANCHOR=/etc/pki/ca-trust/source/anchors/cube-advisor.crt
# The identity an enrolled node holds. config_advisor.cpp names the same paths
# (it decides from them whether the agent should run and migrates them across
# an upgrade); repeated here because hex_sdk cannot read the C header.
ADVISOR_IDENTITY_DIR=/etc/cube/advisor-agent
ADVISOR_AGENT_CERT=$ADVISOR_IDENTITY_DIR/agent.crt
# The action level and consent this cluster serves (ADR 0011/0017), read by the
# agent at startup and authoritative there. Absent means the fail-closed default.
# The vocabulary is the agent's; the two lists below track it by hand.
ADVISOR_LEVEL_FILE=$ADVISOR_IDENTITY_DIR/action-level
ADVISOR_CONSENT_FILE=$ADVISOR_IDENTITY_DIR/consent
# Where this node enrolled, so `advisor upgrade` knows whom to ask. Written at
# enrol from the token; older nodes fall back to the tunnel host on 443.
ADVISOR_URL_FILE=$ADVISOR_IDENTITY_DIR/advisor-url
# The agent release the Advisor named as current at the last connect. The
# agent writes it (cube-advisor-agent#52); nothing here acts on it unasked.
ADVISOR_CURRENT_RELEASE_FILE=$ADVISOR_IDENTITY_DIR/current-release
ADVISOR_AGENT_KEY=$ADVISOR_IDENTITY_DIR/agent.key
# The Advisor's SSH user CA, and the sshd drop-in that trusts it. Both are in
# config_advisor.cpp's migrate list so a console survives a firmware upgrade;
# these are the paths that write them.
ADVISOR_CONSOLE_CA=/etc/ssh/console-ca/cube-advisor.pub
ADVISOR_SSHD_DROPIN=/etc/ssh/sshd_config.d/60-cube-advisor-console.conf
# The account a console certificate authorises. CubeCOS provisions it; the
# Advisor must be configured with the same name or sshd refuses the principal.
ADVISOR_CONSOLE_ACCOUNT=advisor
ADVISOR_MANIFEST_NAME=manifest.txt
ADVISOR_SIGNATURE_NAME=manifest.txt.sig

# The agent's own unit, shipped by cube-advisor-agent and installed with the
# image. Never enabled: hex_config decides when it runs (the advisor module's
# Commit), and advisor_agent_service_start starts it the moment a node enrols.
ADVISOR_AGENT_UNIT_NAME=cube-advisor-agent.service
ADVISOR_AGENT_UNIT=/usr/lib/systemd/system/$ADVISOR_AGENT_UNIT_NAME

# The node-local allowlist the agent may dial: symbolic name -> address. The
# Advisor never learns the address. A name missing here is one the agent
# refuses to dial, so nothing in this module repairs this file.
ADVISOR_TARGETS_FILE=/etc/cube-advisor-agent/web-targets.json

# What discovery found installed, "name host:port" per line. Only a node with
# the framework kubeconfig can see this, so it is fanned out; each node's own
# commit turns it into allowlist entries. The set, not an address: the ingress
# exists from the framework's install, before CMP is installed.
ADVISOR_DISCOVERED_FILE=/etc/cube-advisor-agent/discovered-targets

# The Advisor console origins keystone should trust for Skyline WebSSO, as the
# Advisor reported them, propagated to every control node. config_advisor.cpp
# migrates this file; the two below are rebuilt from it by advisor_sso_apply.
ADVISOR_SSO_REPORTED_FILE=/etc/cube-advisor-agent/sso-origins-reported
# Where the agent writes what the Advisor told it on connect, one
# "<target> <origin-base>" per line. Only on an enrolled node -- the agent runs
# nowhere else -- which is why the reported set is propagated from here rather
# than read directly: keystone answers on every control node, enrolled or not.
ADVISOR_SSO_AGENT_REPORT=$ADVISOR_IDENTITY_DIR/console-origins
# The target whose federated login returns through the console, and the path it
# returns on. Skyline's, because it is the only cluster app that borrows
# keystone's own SAML service provider and so the only one keystone has to be
# told about.
ADVISOR_SSO_TARGET=cube-cos-skyline
ADVISOR_SSO_CALLBACK_PATH=/api/openstack/skyline/api/v1/websso
# Keycloak's admin console needs its origin listed or the session-check iframe
# 403s and the UI spins. Its built-in client, so terraform does not fight it.
ADVISOR_SSO_KEYCLOAK_CLIENT=security-admin-console
# The target whose origin Keycloak is served on. CubeCOS puts Keycloak and
# Rancher on one port, so this is the same origin the tab labels Rancher.
ADVISOR_SSO_IDP_TARGET=cube-cos-idp
ADVISOR_SSO_KEYCLOAK_CONSOLE_PATH=/auth/admin/master/console/*
ADVISOR_KEYCLOAK_PASSWORD_FILE=/etc/cube/cos/terraform/values/keycloak-admin-password.tfvars
# What was last added to that client, so withdrawing an origin removes exactly
# what this added and nothing else. Without it there is no telling an entry
# this put there from one an operator did, and tidying up would delete theirs.
ADVISOR_SSO_KEYCLOAK_STATE=/etc/cube-advisor-agent/sso-keycloak-applied
# Read by cube_mellon_wsgi.py at import and merged into trusted_dashboard.
ADVISOR_SSO_KEYSTONE_FILE=/etc/keystone/cube-advisor-origins
# Sorts after v3_mellon_keycloak_master.conf, which is what lets it win the
# MellonRedirectDomains merge for <Location /v3>.
ADVISOR_SSO_MELLON_FILE=/etc/httpd/conf.d/zz-cube-advisor-mellon.conf

# advisor_verify_release <dir> [artifact]
#
# Manifest signature against the image's key, then every digest it lists. With
# <artifact>, that one must also be named. Anything but 0 is a refusal.
advisor_verify_release()
{
    # artifact is optional; default it so a one-argument call is not an
    # unbound-variable error under set -u.
    local dir=$1 artifact=${2:-}

    if [ -z "$dir" ] ; then
        echo "Error: advisor_verify_release: no release directory given" >&2
        return 1
    fi

    # Branch rather than leaving $artifact unquoted: an empty positional would
    # be a second argument, and an unquoted one would word-split.
    if [ -n "$artifact" ] ; then
        $HEX_CFG advisor_verify_release "$dir" "$artifact"
    else
        $HEX_CFG advisor_verify_release "$dir"
    fi
}

# advisor_release_version <dir>
#
# The version a manifest records. Only call it on one advisor_verify_release
# has accepted: it reads a comment line.
advisor_release_version()
{
    local dir=$1
    awk -F': *' '/^# version:/ { print $2 ; exit }' "$dir/$ADVISOR_MANIFEST_NAME" 2>/dev/null
}

# advisor_install_release <dir> <artifact> <dest>
#
# Verifies then installs. The two are one function on purpose: an install path
# that can be called without verifying is an install path that eventually is.
advisor_install_release()
{
    local dir=$1 artifact=$2 dest=$3

    if [ -z "$artifact" ] || [ -z "$dest" ] ; then
        echo "Error: advisor_install_release: usage <dir> <artifact> <dest>" >&2
        return 1
    fi
    # Passing the artifact makes "is this file covered by the signature?" part of
    # the same verification, rather than a second check that could be skipped. A
    # file that happens to sit in a verified directory is not itself verified.
    advisor_verify_release "$dir" "$artifact" || return 1

    install -m 0755 -o root -g root "$dir/$artifact" "$dest" || return 1
    echo "Installed $artifact $(advisor_release_version "$dir") to $dest"
    return 0
}

# advisor_agent_service_start
#
# Start the tunnel now, so a freshly enrolled node connects instead of holding
# an unused identity. Started, never enabled: hex_config owns when it runs.
advisor_agent_service_start()
{
    if [ ! -r "$ADVISOR_AGENT_UNIT" ] ; then
        echo "Warning: $ADVISOR_AGENT_UNIT is missing; the tunnel cannot be started" >&2
        return 0
    fi

    # restart, not start: a forced re-enrolment replaces the identity under a
    # running agent, which otherwise keeps its old connection open and the new
    # identity never dials in. On a stopped unit restart is a start.
    if systemctl restart "$ADVISOR_AGENT_UNIT_NAME" >/dev/null 2>&1 ; then
        echo "Tunnel service started; hex_config starts it on every boot from here."
    else
        # The identity is saved and enrolment did succeed, so this must not
        # fail the command -- say what is wrong and let the operator start it.
        echo "Warning: could not start $ADVISOR_AGENT_UNIT_NAME; start it manually with: systemctl start $ADVISOR_AGENT_UNIT_NAME" >&2
    fi
    return 0
}

# advisor_cluster_id
#
# The cluster's identity for enrolment, chosen once and effectively permanent
# (the Advisor keys five tables on it). CUBE_CLUSTER_ID from the driver first --
# unique by construction -- then cubesys.controller, which is the same on every
# node but can collide across sites. Never the hostname: a 3-node cluster would
# enrol as whichever node the operator typed on.
advisor_cluster_id()
{
    local id=""

    if [ -r /etc/cube/phone-home-agent.env ] ; then
        id=$(sed -n 's/^CUBE_CLUSTER_ID=//p' /etc/cube/phone-home-agent.env | head -1)
    fi
    if [ -z "$id" ] ; then
        id=$(source /usr/sbin/hex_tuning /etc/settings.txt 2>/dev/null ; echo "${T_cubesys_controller:-}")
    fi
    # Last resort: the certificate is migrated across a firmware upgrade while
    # the two sources above are not. Last, not first -- they say what this
    # cluster is now, the certificate what it enrolled as once.
    if [ -z "$id" ] && [ -r "$ADVISOR_AGENT_CERT" ] ; then
        id=$(openssl x509 -in "$ADVISOR_AGENT_CERT" -noout -subject -nameopt multiline 2>/dev/null |
             sed -n 's/^ *organizationalUnitName *= *//p' | head -1)
    fi
    if [ -z "$id" ] ; then
        echo "Error: cannot tell which cluster this node belongs to (no CUBE_CLUSTER_ID, no cubesys.controller, no enrolled identity)" >&2
        return 1
    fi

    # It becomes a certificate CN and a URL path segment, and nothing on the
    # Advisor side validates either -- so refuse the shapes that would break
    # them here, where the message can still be useful.
    case $id in
        */*|*\ *) echo "Error: cluster id contains a character that cannot appear in a URL path: $id" >&2 ; return 1 ;;
    esac
    if [ ${#id} -gt 64 ] ; then
        echo "Error: cluster id is longer than 64 characters, which strict X.509 tooling rejects: $id" >&2
        return 1
    fi

    echo "$id"
}

# advisor_agent_arch
#
# This machine's artifact name in the manifest. An unknown architecture is a
# refusal, not a guess.
advisor_agent_arch()
{
    local m
    m=$(uname -m)
    case "$m" in
        x86_64)  echo amd64 ;;
        aarch64) echo arm64 ;;
        *)       echo "Error: no Advisor agent build for $m" >&2 ; return 1 ;;
    esac
}

# _advisor_target_name_valid <name>
#
# name is a URL path segment on the agent's own local dial API and becomes a
# JSON object key here, so both ends care about its shape.
_advisor_target_name_valid()
{
    case $1 in
        '') return 1 ;;
    esac
    case $1 in
        [a-z0-9]*) : ;;
        *) return 1 ;;
    esac
    case $1 in
        *[!a-z0-9-]*) return 1 ;;
    esac
    return 0
}

# _advisor_target_address_valid <host:port>
#
# advisor_targets_set's shape, checked silently: these lines come from
# discovery, not from someone typing.
_advisor_target_address_valid()
{
    local host port

    case $1 in
        *:*) : ;;
        *) return 1 ;;
    esac
    host=${1%:*}
    port=${1##*:}
    case $host in
        ''|*[!A-Za-z0-9.-]*) return 1 ;;
    esac
    case $port in
        ''|*[!0-9]*|0?*) return 1 ;;
    esac
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

# _advisor_write_file <path> <content>
#
# Atomic write (temp file in the same directory, then mv): the agent reads
# these at any moment and must never see half of one.
_advisor_write_file()
{
    local path=$1 content=$2
    local dir tmp

    dir=$(dirname "$path")
    mkdir -p "$dir" || return 1

    tmp=$(mktemp "$dir/$(basename "$path").XXXXXX") || return 1
    if ! printf '%s\n' "$content" > "$tmp" ; then
        rm -f "$tmp"
        return 1
    fi
    if ! chmod 0644 "$tmp" || ! chown root:root "$tmp" ; then
        rm -f "$tmp"
        return 1
    fi
    if ! mv -f "$tmp" "$path" ; then
        rm -f "$tmp"
        return 1
    fi
}

# _advisor_targets_write <json>
#
# Writes the allowlist.
_advisor_targets_write()
{
    _advisor_write_file "$ADVISOR_TARGETS_FILE" "$1"
}

# advisor_discovered_set <name> <host:port> [<name> <host:port> ...]
#
# Records what discovery found, replacing the file outright: the argument list
# is the whole answer. What it becomes is advisor_targets_init's business.
advisor_discovered_set()
{
    local name target content="" nl='
'

    if [ $# -lt 2 ] || [ $(($# % 2)) -ne 0 ] ; then
        echo "Error: advisor_discovered_set: usage <name> <host:port> [<name> <host:port> ...]" >&2
        return 1
    fi

    while [ $# -ge 2 ] ; do
        name=$1 ; target=$2 ; shift 2
        if ! _advisor_target_name_valid "$name" ; then
            echo "Error: not a valid target name: $name" >&2
            return 1
        fi
        if ! _advisor_target_address_valid "$target" ; then
            echo "Error: not a literal host:port: $target" >&2
            return 1
        fi
        content="$content${content:+$nl}$name $target"
    done

    _advisor_write_file "$ADVISOR_DISCOVERED_FILE" "$content"
}

# advisor_discovered_list
#
# The recorded set, one "name host:port" per line; silent when absent (a
# cluster with no app framework). Every line is rechecked.
advisor_discovered_list()
{
    local name target extra

    [ -r "$ADVISOR_DISCOVERED_FILE" ] || return 0
    while read -r name target extra ; do
        [ -n "$name" ] && [ -n "$target" ] && [ -z "$extra" ] || continue
        _advisor_target_name_valid "$name" || continue
        _advisor_target_address_valid "$target" || continue
        echo "$name $target"
    done < "$ADVISOR_DISCOVERED_FILE"
}

# advisor_targets_init
#
# Seeds the allowlist on a node that has none: this cluster's own targets plus
# what discovery recorded here. Seeds, never reconciles -- a file already there
# is left exactly as the operator left it.
# advisor_dashboard_address
#
# Where this cluster's web UI answers: the control VIP, else this node's
# management address. Not 127.0.0.1:8080 -- that httpd answers 403.
advisor_dashboard_address()
{
    local addr

    addr=$(source /usr/sbin/hex_tuning /etc/settings.txt 2>/dev/null ; echo "${T_cubesys_control_vip:-}")
    if [ -z "$addr" ] ; then
        addr=$(source /usr/sbin/hex_tuning /etc/settings.txt 2>/dev/null
               eval echo "\${T_net_if_addr_${T_cubesys_management}:-}")
    fi
    [ -n "$addr" ] || return 1
    echo "$addr:443"
}

# advisor_own_targets
#
# What every node can name for itself: this cluster's dashboard and the
# endpoints it links out to on other ports. Each needs allowing in its own
# right -- the dashboard builds those URLs in script, so no proxy rewrites them.
advisor_own_targets()
{
    local dash addr

    dash=$(advisor_dashboard_address) || return 1
    addr="${dash%:*}"
    echo "cube-cos $dash"
    echo "cube-cos-idp $addr:10443"
    echo "cube-cos-skyline $addr:9999"
    echo "cube-cos-ceph $addr:7443"
    # Skyline's federated login leaves Skyline for keystone and then mellon.
    # Companions of cube-cos-skyline, but dialled by name, so each is listed.
    echo "cube-cos-keystone $addr:5000"
    echo "cube-cos-keystone-sso $addr:5443"
}

advisor_targets_init()
{
    local discovered own all

    [ -e "$ADVISOR_TARGETS_FILE" ] && return 0

    # awk, not a read loop: a loop on the right of a pipe runs in a subshell
    # and would leave the string it built behind in it.
    discovered=$(advisor_discovered_list | awk '{ printf ",\"%s\":\"%s\"", $1, $2 }')
    # Empty when this node has no address yet: seed no dashboard rather than
    # one that refuses every request; advisor target_set adds it once the
    # address is known.
    own=$(advisor_own_targets 2>/dev/null | awk '{ printf ",\"%s\":\"%s\"", $1, $2 }')
    all="$own$discovered"
    _advisor_targets_write "{${all#,}}"
}

# advisor_targets_list
#
# The current allowlist, one "name host:port" per line. Read with jq, not a
# regex: the file is hand-edited and reformatted by whatever touched it last.
advisor_targets_list()
{
    [ -r "$ADVISOR_TARGETS_FILE" ] || return 0
    jq -r 'to_entries[] | "\(.key) \(.value)"' "$ADVISOR_TARGETS_FILE" 2>/dev/null
}

# advisor_targets_set <name> <host:port>
#
# Adds or replaces an entry. Validated here, where the message can still help
# someone: the agent dials whatever this file says.
advisor_targets_set()
{
    local name=$1 target=$2
    local host port new rc

    if [ -z "$name" ] || [ -z "$target" ] ; then
        echo "Error: advisor_targets_set: usage <name> <host:port>" >&2
        return 1
    fi
    if ! _advisor_target_name_valid "$name" ; then
        echo "Error: target name must start with a lowercase letter or digit and contain only lowercase letters, digits and hyphens: $name" >&2
        return 1
    fi

    case $target in
        *:*) : ;;
        *) echo "Error: target must be host:port: $target" >&2 ; return 1 ;;
    esac
    host=${target%:*}
    port=${target##*:}
    # The SaaS side accepts an IPv6 pool address; a node does not. Say so,
    # rather than let this fall into the generic "not a literal host" refusal.
    case $host in
        *:*) echo "Error: IPv6 addresses are not supported as a target host (only a literal IPv4 address or hostname): $host" >&2 ; return 1 ;;
    esac
    case $host in
        ''|*[!A-Za-z0-9.-]*) echo "Error: not a literal host: $host" >&2 ; return 1 ;;
    esac
    case $port in
        ''|*[!0-9]*) echo "Error: port is not numeric: $port" >&2 ; return 1 ;;
    esac
    case $port in
        0?*) echo "Error: port must not have a leading zero: $port" >&2 ; return 1 ;;
    esac
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ] ; then
        echo "Error: port out of range (1-65535): $port" >&2
        return 1
    fi

    # -e: an unparseable file is a refusal, never "start from nothing". An
    # empty one still needs catching by hand -- jq calls zero inputs success.
    if [ -e "$ADVISOR_TARGETS_FILE" ] ; then
        new=$(jq -e --arg n "$name" --arg v "$target" \
              'if type == "object" then .[$n] = $v else error("not a JSON object") end' \
              "$ADVISOR_TARGETS_FILE" 2>/dev/null)
        rc=$?
    else
        new=$(jq -n -e --arg n "$name" --arg v "$target" '{($n): $v}')
        rc=$?
    fi
    if [ $rc -ne 0 ] || [ -z "$new" ] ; then
        echo "Error: $ADVISOR_TARGETS_FILE does not read as a JSON object; nothing changed" >&2
        return 1
    fi
    _advisor_targets_write "$new"
}

# advisor_targets_unset <name>
#
# Removes one entry. Removing a name that is not there is not an error -- the
# file already says what the operator wants.
advisor_targets_unset()
{
    local name=$1 new rc

    if [ -z "$name" ] ; then
        echo "Error: advisor_targets_unset: usage <name>" >&2
        return 1
    fi
    if ! _advisor_target_name_valid "$name" ; then
        echo "Error: not a valid target name: $name" >&2
        return 1
    fi

    # Nothing to remove from an allowlist that does not exist yet.
    [ -e "$ADVISOR_TARGETS_FILE" ] || return 0

    new=$(jq -e --arg n "$name" \
          'if type == "object" then del(.[$n]) else error("not a JSON object") end' \
          "$ADVISOR_TARGETS_FILE" 2>/dev/null)
    rc=$?
    if [ $rc -ne 0 ] || [ -z "$new" ] ; then
        echo "Error: $ADVISOR_TARGETS_FILE does not read as a JSON object; nothing changed" >&2
        return 1
    fi
    _advisor_targets_write "$new"
}

# _advisor_agent_reload_setting
#
# Makes a level or consent change take effect: the agent reads both files once,
# at startup. Restart, not reload -- it has no reload path for these.
_advisor_agent_reload_setting()
{
    systemctl is-active --quiet "$ADVISOR_AGENT_UNIT_NAME" || return 0
    if ! systemctl restart "$ADVISOR_AGENT_UNIT_NAME" >/dev/null 2>&1 ; then
        echo "Warning: wrote the setting but could not restart $ADVISOR_AGENT_UNIT_NAME;" \
             "it takes effect on the next start" >&2
    fi
}

# advisor_level_set <observe|operate|internal>
#
# Records the action level this cluster serves (ADR 0011), in the file the
# agent reads as authoritative. The vocabulary is the agent's.
advisor_level_set()
{
    local level=$1
    case "$level" in
        observe|operate|internal) ;;
        *)
            echo "Error: not an action level: '$level'; expected observe, operate or internal" >&2
            return 1
            ;;
    esac
    _advisor_write_file "$ADVISOR_LEVEL_FILE" "$level" || return 1
    _advisor_agent_reload_setting
}

# advisor_consent_set <always|destructive|never>
#
# How much this cluster asks a person before the agent acts (ADR 0011). Same
# custody as the level.
advisor_consent_set()
{
    local consent=$1
    case "$consent" in
        always|destructive|never) ;;
        *)
            echo "Error: not a consent setting: '$consent'; expected always, destructive or never" >&2
            return 1
            ;;
    esac
    _advisor_write_file "$ADVISOR_CONSENT_FILE" "$consent" || return 1
    _advisor_agent_reload_setting
}

# advisor_level_show
#
# The level and consent this node serves, "<field> <value>" per line. An absent
# file reads as the agent's fail-closed default rather than a blank.
advisor_level_show()
{
    local level consent
    level=$(head -n1 "$ADVISOR_LEVEL_FILE" 2>/dev/null | tr -d '[:space:]')
    consent=$(head -n1 "$ADVISOR_CONSENT_FILE" 2>/dev/null | tr -d '[:space:]')
    [ -n "$level" ] || level="unset (observe)"
    [ -n "$consent" ] || consent="unset (always)"
    echo "level $level"
    echo "consent $consent"
}

# advisor_targets_discover
#
# Publishes the set of web targets actually installed, from the one node with
# the kubeconfig to every node (each node's commit turns it into allowlist
# entries). Presence is decided per target from its Helm release, not the
# ingress: the ingress predates CMP's install. CMP and its IdP share one
# address deliberately -- one origin, or the OIDC state cookie is orphaned.
#
# Called by the installers and by enrolment; idempotent, last call wins. On
# this node it also sets the names outright, which does bring back a name an
# operator unset -- the caller is an install declaring that endpoint again.
# _advisor_discard_kubeconfig <path>
#
# Removes a kubeconfig this module fetched and unsets the export. No-op for the
# empty path a caller-supplied APPFW_KUBECONFIG leaves.
_advisor_discard_kubeconfig()
{
    [ -n "${1:-}" ] || return 0
    rm -f "$1"
    unset APPFW_KUBECONFIG
}

advisor_targets_discover()
{
    local addr node pairs="" kc=""

    # One kubeconfig for the three queries below, fetched here rather than in
    # each helper: they run as separate hex_sdk processes, so a helper that
    # fetched its own would authenticate to rancher three times per call.
    # Exported because that is how those processes receive it.
    if [ -z "${APPFW_KUBECONFIG:-}" ] ; then
        kc=$($HEX_SDK app_kubeconfig) || return 0
        export APPFW_KUBECONFIG=$kc
    fi

    addr=$($HEX_SDK app_ingress_address) || { _advisor_discard_kubeconfig "$kc" ; return 0 ; }
    [ -n "$addr" ] || { _advisor_discard_kubeconfig "$kc" ; return 0 ; }

    # The app framework's own Keycloak, and the CMP portal. Each is declared by
    # whatever installed it, at the moment it is found installed.
    $HEX_SDK app_helm_release_deployed keycloak && pairs="$pairs app-fw-idp $addr:443"
    $HEX_SDK app_helm_release_deployed cube-portal && pairs="$pairs cube-cmp $addr:443"
    _advisor_discard_kubeconfig "$kc"
    [ -n "$pairs" ] || return 0

    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        remote_run $node "$HEX_SDK advisor_discovered_set$pairs" >/dev/null 2>&1 || \
            echo "Warning: could not record the discovered targets on $node; it picks them up at its next commit" >&2
    done

    # A cluster that never enrolled must not gain an allowlist from installing
    # CMP. The fan-out above is before this guard on purpose: an install runs
    # long before enrolment, and advisor_targets_init seeds from what it left.
    [ -e "$ADVISOR_TARGETS_FILE" ] || return 0

    set -- $pairs
    while [ $# -ge 2 ] ; do
        advisor_targets_set "$1" "$2"
        shift 2
    done
    return 0
}

# _advisor_sso_origin_valid <url>
#
# A WebSSO callback URL keystone may post a token to -- the matched origin
# becomes the form action, so this authorises sending an unscoped token there.
# https only, no userinfo, no query or fragment, "*" only in the host: the
# shape keystone's patched _origin_matches compares.
_advisor_sso_origin_valid()
{
    local rest host port path

    case $1 in
        https://*) rest=${1#https://} ;;
        *) return 1 ;;
    esac
    # Anything that could move the authority: userinfo, or a second authority.
    case $rest in
        ''|*@*|*' '*|*'	'*) return 1 ;;
    esac
    path=/${rest#*/}
    host=${rest%%/*}
    [ "$host" != "$rest" ] || return 1
    # A conservative whitelist rather than a list of what to reject. These
    # strings come from the Advisor and reach keystone's config and a remote
    # shell; a callback path has no need of a quote, space or metacharacter.
    case $path in
        *[!A-Za-z0-9._~%/-]*) return 1 ;;
    esac
    case $host in
        *:*) port=${host##*:} ; host=${host%:*} ;;
        *) port= ;;
    esac
    if [ -n "$port" ] ; then
        case $port in
            ''|*[!0-9]*|0?*) return 1 ;;
        esac
        [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
    fi
    case $host in
        ''|*[!A-Za-z0-9.*-]*) return 1 ;;
    esac
    return 0
}

# _advisor_sso_base_valid <origin-base>
#
# "https://host[:port]" and nothing more -- a consumer appends its own path.
# "*" allowed in the host, for a mode that puts the session id there.
_advisor_sso_base_valid()
{
    local rest host port

    case $1 in
        https://*) rest=${1#https://} ;;
        *) return 1 ;;
    esac
    case $rest in
        ''|*/*|*@*|*' '*|*'	'*) return 1 ;;
    esac
    case $rest in
        *:*) host=${rest%:*} ; port=${rest##*:} ;;
        *) host=$rest ; port= ;;
    esac
    if [ -n "$port" ] ; then
        case $port in
            ''|*[!0-9]*|0?*) return 1 ;;
        esac
        [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
    fi
    case $host in
        ''|*[!A-Za-z0-9.*-]*) return 1 ;;
    esac
    return 0
}

# advisor_sso_reported_bases
#
# What the Advisor reported, "<target> <origin-base>" per line. The raw report
# travels, not a composed URL: keystone wants a callback URL, mellon hostnames
# without ports, Keycloak an origin with its port. Every line is rechecked --
# this file crosses a node boundary and a firmware upgrade.
advisor_sso_reported_bases()
{
    local target base extra

    [ -r "$ADVISOR_SSO_REPORTED_FILE" ] || return 0
    while read -r target base extra ; do
        [ -n "$target" ] && [ -n "$base" ] && [ -z "$extra" ] || continue
        case $target in '#'*) continue ;; esac
        _advisor_target_name_valid "$target" || continue
        _advisor_sso_base_valid "$base" || continue
        echo "$target $base"
    done < "$ADVISOR_SSO_REPORTED_FILE"
}

# advisor_sso_reported_base <target>
#
# One target's reported origin base, empty when it was not reported.
advisor_sso_reported_base()
{
    advisor_sso_reported_bases | awk -v t="$1" '$1 == t { print $2 ; exit }'
}

# advisor_sso_reported_list
#
# What keystone should trust: Skyline's callback URL, composed from the
# reported base. A session wildcard is kept -- keystone's patched matcher
# globs the host, the only form that can name a per-session origin.
advisor_sso_reported_list()
{
    local base url

    base=$(advisor_sso_reported_base "$ADVISOR_SSO_TARGET")
    [ -n "$base" ] || return 0
    url="${base%/}$ADVISOR_SSO_CALLBACK_PATH"
    _advisor_sso_origin_valid "$url" || return 0
    echo "$url"
}

# advisor_sso_effective_list
#
# What is actually trusted. The Advisor's report is the only source: it is live
# truth, and it withdraws itself when the Advisor stops claiming an origin.
advisor_sso_effective_list()
{
    advisor_sso_reported_list | awk '!seen[$0]++'
}

# advisor_sso_origins_show
#
# What this node trusts, and who said so -- an operator looking at an origin
# they did not choose needs to see that nobody here declared it.
advisor_sso_origins_show()
{
    local url

    advisor_sso_effective_list | while read -r url ; do
        echo "$url (reported by the Advisor)"
    done
}

# advisor_sso_report_read
#
# The agent's report as "<target> <origin-base>" lines this release accepts,
# whole rather than composed (see advisor_sso_reported_bases).
advisor_sso_report_read()
{
    local target base extra

    [ -r "$ADVISOR_SSO_AGENT_REPORT" ] || return 0
    while read -r target base extra ; do
        [ -n "$target" ] && [ -n "$base" ] && [ -z "$extra" ] || continue
        _advisor_target_name_valid "$target" || continue
        _advisor_sso_base_valid "$base" || continue
        echo "$target $base"
    done < "$ADVISOR_SSO_AGENT_REPORT"
}

# advisor_sso_report_apply
#
# What the agent's report turns into, cluster-wide. Called at enrolment and by
# health_advisor_repair, which is what notices a report that arrives once the
# node's fingerprint is verified. Propagated rather than read in place: the
# agent runs on enrolled nodes, keystone on every control node behind the VIP.
advisor_sso_report_apply()
{
    local node word args="" rc=0

    # Only a node holding an identity speaks for the Advisor. On any other the
    # report's absence means "no agent here", not "the Advisor reports no
    # console origin" -- and acting on that would withdraw the whole cluster's
    # trust from a node that was never told anything.
    [ -e "$ADVISOR_AGENT_CERT" ] || return 0

    # Alternating name and base, the shape advisor_discovered_set already uses
    # for the other set this fans out. Neither can carry a space: both are
    # rechecked at the far end anyway.
    for word in $(advisor_sso_report_read) ; do
        args="$args '$word'"
    done

    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! remote_run "$node" "$HEX_SDK advisor_sso_reported_set$args && $HEX_SDK advisor_sso_apply" >/dev/null 2>&1 ; then
            echo "Warning: could not carry the Advisor's console origins to $node; Skyline federated login will fail whenever that node answers" >&2
            rc=1
        fi
    done
    return $rc
}

# advisor_sso_reported_set [<target> <origin-base> ...]
#
# Records the Advisor's report on this node. No arguments withdraws it, which
# is what a report naming no console origin means.
advisor_sso_reported_set()
{
    local target base content="" nl='
'

    if [ $(($# % 2)) -ne 0 ] ; then
        echo "Error: advisor_sso_reported_set: usage [<target> <origin-base> ...]" >&2
        return 1
    fi
    while [ $# -ge 2 ] ; do
        target=$1 ; base=$2 ; shift 2
        if ! _advisor_target_name_valid "$target" ; then
            echo "Error: not a valid target name: $target" >&2
            return 1
        fi
        if ! _advisor_sso_base_valid "$base" ; then
            echo "Error: not an https origin base: $base" >&2
            return 1
        fi
        content="$content${content:+$nl}$target $base"
    done

    if [ -z "$content" ] ; then
        rm -f "$ADVISOR_SSO_REPORTED_FILE"
        return 0
    fi
    _advisor_write_file "$ADVISOR_SSO_REPORTED_FILE" "$content"
}

# _advisor_sso_hosts
#
# The host of each trusted origin, deduplicated -- what mellon matches on.
_advisor_sso_hosts()
{
    local url host

    advisor_sso_effective_list | while read -r url ; do
        host=${url#https://}
        host=${host%%/*}
        echo "${host%:*}"
    done | sort -u
}

# _advisor_keycloak_token <base-url>
#
# An admin token for the local Keycloak, from the password terraform keeps.
# Empty on any failure: every caller then leaves Keycloak alone.
_advisor_keycloak_token()
{
    local base=$1 pw

    pw=$(sed -n 's/^keycloak_admin_password *= *"\?\([^"]*\)"\?.*/\1/p' \
         "$ADVISOR_KEYCLOAK_PASSWORD_FILE" 2>/dev/null)
    [ -n "$pw" ] || return 0

    curl -sk --max-time 20 \
        -d "client_id=admin-cli" -d "username=admin" --data-urlencode "password=$pw" \
        -d "grant_type=password" \
        "$base/auth/realms/master/protocol/openid-connect/token" 2>/dev/null |
        sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

# advisor_sso_keycloak_apply
#
# Lets Keycloak's admin console load on the Advisor's console origins: its
# client's web origins are derived from this cluster's own address, so the
# Advisor's is refused and the session-check iframe 403s.
#
# Idempotent, and removes only origins it added (recorded in
# ADVISOR_SSO_KEYCLOAK_STATE). Best effort: an unreachable Keycloak must not
# fail a commit.
advisor_sso_keycloak_apply()
{
    local base tok cid origins prev

    base=$(advisor_dashboard_address 2>/dev/null) || return 0
    base="https://${base%:*}:10443"
    tok=$(_advisor_keycloak_token "$base")
    [ -n "$tok" ] || return 0

    # jq, not a regex: the client object nests other objects with their own
    # "id", and a greedy match picks the last one -- which is a real client id,
    # so the write lands on some other client and quietly does nothing here.
    cid=$(curl -sk --max-time 20 -H "Authorization: Bearer $tok" \
          "$base/auth/admin/realms/master/clients?clientId=$ADVISOR_SSO_KEYCLOAK_CLIENT" 2>/dev/null |
          jq -r '.[0].id // empty' 2>/dev/null)
    [ -n "$cid" ] || return 0

    # The identity provider's own origin, with its port: Keycloak compares the
    # browser's Origin header, which carries one. Not _advisor_sso_hosts --
    # that drops the port because mellon matches hostnames, and an origin
    # without a port matches nothing here.
    origins=$(advisor_sso_reported_base "$ADVISOR_SSO_IDP_TARGET")
    prev=$(tr '\n' ' ' < "$ADVISOR_SSO_KEYCLOAK_STATE" 2>/dev/null)

    curl -sk --max-time 20 -H "Authorization: Bearer $tok" \
        "$base/auth/admin/realms/master/clients/$cid" 2>/dev/null |
        ADVISOR_ORIGINS="$origins" ADVISOR_PREV="$prev" \
        ADVISOR_CONSOLE_PATH="$ADVISOR_SSO_KEYCLOAK_CONSOLE_PATH" \
        python3 -c '
import json, os, sys

path = os.environ["ADVISOR_CONSOLE_PATH"]
want = set(os.environ["ADVISOR_ORIGINS"].split())
# Only what this added before may be taken away. Anything else in the client
# was put there by somebody else and is not ours to tidy up.
stale = set(os.environ["ADVISOR_PREV"].split()) - want

try:
    c = json.load(sys.stdin)
except Exception:
    sys.exit(1)

c["webOrigins"] = sorted((set(c.get("webOrigins", [])) - stale) | want)
c["redirectUris"] = sorted(
    (set(c.get("redirectUris", [])) - {o + path for o in stale}) | {o + path for o in want})
json.dump(c, sys.stdout)
' > /tmp/.advisor-kc-client.$$ 2>/dev/null

    # -f, so an HTTP error is a failure: without it curl exits 0 on a 4xx and
    # the state below records an origin Keycloak never accepted.
    if [ -s /tmp/.advisor-kc-client.$$ ] &&
       curl -skf --max-time 20 -X PUT -H "Authorization: Bearer $tok" \
           -H "Content-Type: application/json" --data @/tmp/.advisor-kc-client.$$ \
           "$base/auth/admin/realms/master/clients/$cid" >/dev/null 2>&1 ; then
        # Recorded only once Keycloak accepted it, so a failed push does not
        # leave this believing it added something it did not.
        if [ -n "$origins" ] ; then
            _advisor_write_file "$ADVISOR_SSO_KEYCLOAK_STATE" "$origins"
        else
            rm -f "$ADVISOR_SSO_KEYCLOAK_STATE"
        fi
    fi
    rm -f /tmp/.advisor-kc-client.$$
    return 0
}

# advisor_sso_apply
#
# Rebuilds the two files Skyline's WebSSO needs from the recorded origins, and
# writes them only when they changed. Both are derived, so neither is migrated.
#
#   keystone   cube_mellon_wsgi.py merges this into trusted_dashboard at import;
#              keystone.conf cannot carry it (config_keystone.cpp owns
#              [federation]).
#   mellon     a later <Location /v3> wins the MellonRedirectDomains merge, so
#              v3_mellon_keycloak_master.conf stays keystone_idp's.
advisor_sso_apply()
{
    local origins hosts keystone_body mellon_body

    origins=$(advisor_sso_effective_list)
    hosts=$(_advisor_sso_hosts)

    keystone_body=$origins
    if [ -n "$hosts" ] ; then
        # [self] is mellon's default and is dropped the moment this directive
        # is given at all; keystone's own redirects need it back.
        mellon_body="<Location /v3>
    MellonRedirectDomains [self] $(echo $hosts)
</Location>"
    else
        mellon_body=""
    fi

    if _advisor_sso_file_changed "$ADVISOR_SSO_KEYSTONE_FILE" "$keystone_body" ; then
        if [ -n "$keystone_body" ] ; then
            _advisor_write_file "$ADVISOR_SSO_KEYSTONE_FILE" "$keystone_body" || return 1
        else
            rm -f "$ADVISOR_SSO_KEYSTONE_FILE"
        fi
        # The shim reads the file at import, so the running workers keep the
        # old list until they are replaced. httpd only proxies to them.
        if systemctl is-active --quiet openstack-keystone ; then
            systemctl restart openstack-keystone
        fi
    fi

    # Keycloak keeps its allowlist in its own database, not in a file here, so
    # there is nothing to compare -- the call is idempotent instead.
    advisor_sso_keycloak_apply

    if _advisor_sso_file_changed "$ADVISOR_SSO_MELLON_FILE" "$mellon_body" ; then
        if [ -n "$mellon_body" ] ; then
            _advisor_write_file "$ADVISOR_SSO_MELLON_FILE" "$mellon_body" || return 1
        else
            rm -f "$ADVISOR_SSO_MELLON_FILE"
        fi
        if systemctl is-active --quiet httpd ; then
            systemctl reload httpd
        fi
    fi
    return 0
}

# _advisor_sso_file_changed <path> <content>
#
# True when writing <content> would change <path> ("should not exist" is empty
# content). Not an optimisation: restarting keystone drops logins in progress.
_advisor_sso_file_changed()
{
    local path=$1 content=$2

    if [ -z "$content" ] ; then
        [ -e "$path" ]
        return
    fi
    [ -r "$path" ] || return 0
    [ "$(cat "$path")" != "$content" ]
}

# advisor_enroll <server> <token-file> <version>
#
# Fetch the release, verify it against the image's key, install the agent, enrol
# this cluster. The token comes from a file: on a command line it is visible in
# ps. Every step fails closed -- a half-install is worse than a clean failure.
# advisor_trust_ca <ca-file>
#
# Installs the Advisor's CA into the system trust store: curl and the agent
# both read it, neither takes a CA path, and -k is not an option with a bearer
# token on the request. Not migrated across a firmware upgrade -- this is
# enrolment-time trust; the tunnel pins the enrollment CA, which is migrated.
advisor_trust_ca()
{
    local ca=$1

    [ -n "$ca" ] || return 0
    if [ ! -r "$ca" ] ; then
        echo "Error: cannot read the Advisor CA file: $ca" >&2
        return 1
    fi
    # A file that is not a certificate would install cleanly and then fail
    # every TLS handshake with nothing pointing back here.
    if ! openssl x509 -in "$ca" -noout >/dev/null 2>&1 ; then
        echo "Error: $ca is not a PEM certificate" >&2
        return 1
    fi
    install -m 0644 "$ca" "$ADVISOR_TRUST_ANCHOR" || return 1
    if ! update-ca-trust extract >/dev/null 2>&1 ; then
        echo "Error: could not rebuild this node's trust store" >&2
        rm -f "$ADVISOR_TRUST_ANCHOR"
        return 1
    fi
    echo "Trusting the Advisor's CA from $ca."
    return 0
}

# advisor_console_trust <ca-file>
#
# Makes sshd accept the console certificates the Advisor mints. The CA arrives
# with the identity (agent 0.4.14), so enrolment is the only caller. Both files
# are migrated, so they survive a firmware upgrade.
advisor_console_trust()
{
    local ca=$1

    if [ -z "$ca" ] || [ ! -r "$ca" ] ; then
        echo "Error: cannot read the console CA file: ${ca:-<none>}" >&2
        return 1
    fi
    # One public key in sshd's own authorized-keys form. A private key, or a
    # certificate, would install cleanly and then fail every login with
    # nothing pointing back here.
    if ! ssh-keygen -l -f "$ca" >/dev/null 2>&1 ; then
        echo "Error: $ca is not an SSH public key" >&2
        return 1
    fi
    case $(head -1 "$ca") in
        ssh-*|ecdsa-*|sk-*) : ;;
        *) echo "Error: $ca is not a public key line sshd can read" >&2 ; return 1 ;;
    esac

    mkdir -p "$(dirname "$ADVISOR_CONSOLE_CA")" || return 1
    install -m 0644 "$ca" "$ADVISOR_CONSOLE_CA" || return 1

    # The drop-in is written rather than appended to sshd_config: an append
    # would duplicate on every re-run, and 50-redhat.conf is not ours to edit.
    cat > "$ADVISOR_SSHD_DROPIN" <<EOF
# Managed by CubeCOS. Trusts the Cube AI Advisor's console CA for the
# $ADVISOR_CONSOLE_ACCOUNT account only, so a certificate it signs cannot be
# presented as any other user.
TrustedUserCAKeys $ADVISOR_CONSOLE_CA
Match User $ADVISOR_CONSOLE_ACCOUNT
    AuthorizedPrincipalsCommand /bin/echo $ADVISOR_CONSOLE_ACCOUNT
    AuthorizedPrincipalsCommandUser nobody
EOF
    chmod 0600 "$ADVISOR_SSHD_DROPIN"

    # A drop-in sshd refuses to parse would take sshd down on its next
    # restart, which is a far worse outcome than a console that does not work.
    if ! sshd -t 2>/dev/null ; then
        rm -f "$ADVISOR_SSHD_DROPIN"
        echo "Error: sshd rejected the console configuration; nothing was changed" >&2
        return 1
    fi
    systemctl reload sshd >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || {
        echo "Warning: could not reload sshd; the console starts working after the next reload" >&2
    }
    echo "This node now accepts Advisor console sessions as $ADVISOR_CONSOLE_ACCOUNT."
    return 0
}

# _advisor_token_decode <token-string> <out-dir>
#
# Splits a pasted token into url, secret, ca and console files. python, not
# cut: the token is gzipped JSON behind "cubeadv1.", a format not a delimiter.
_advisor_token_decode()
{
    local token=$1 dir=$2

    ADV_TOKEN="$token" ADV_DIR="$dir" python3 -c '
import base64, gzip, json, os, sys

tok = "".join(os.environ["ADV_TOKEN"].split())
prefix = "cubeadv1."
if not tok.startswith(prefix):
    sys.stderr.write("not an enrolment token\n"); sys.exit(1)
try:
    body = tok[len(prefix):]
    raw = gzip.decompress(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
    e = json.loads(raw)
except Exception:
    sys.stderr.write("the token is malformed\n"); sys.exit(1)

url, secret = e.get("url", ""), e.get("s", "")
if not url.startswith("https://") or not secret:
    sys.stderr.write("the token carries no https URL or no secret\n"); sys.exit(1)

d = os.environ["ADV_DIR"]
def put(name, text, mode):
    path = os.path.join(d, name)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(fd, "w") as f:
        f.write(text)

put("url", url, 0o600)
put("secret", secret, 0o600)
put("console", "true" if e.get("console") else "false", 0o600)
# The action level and consent the issuer chose. Seeds this node; the files
# on the node stay authoritative and level_set / consent_set still override.
for key in ("level", "consent"):
    if e.get(key):
        put(key, str(e[key]), 0o600)
# Optional: a deployment behind a real terminator is covered by the system
# store and the token says nothing here.
if e.get("serverCa"):
    put("ca", e["serverCa"], 0o600)
' || return 1
}

# advisor_enroll_token <token-file> [<version>] [force]
#
# Enrol from what the operator pasted: the token names the Advisor, carries the
# certificate to verify it and holds the secret, and the node asserts its own
# cluster id (cube-ai-advisor#242). A blank <version> asks the Advisor which
# release is current -- the token cannot name one, it is issued earlier.
# advisor_current_release <server> <token-file>
#
# GET /api/v1/releases/current, authenticated by the pairing token, which
# asking does not spend.
advisor_current_release()
{
    local server=$1 token_file=$2 out

    out=$(curl -fsS --max-time 30 \
            -H "Authorization: Bearer $(cat "$token_file")" \
            "$server/api/v1/releases/current") || return 1
    printf '%s' "$out" | python3 -c 'import json,sys; v=json.load(sys.stdin).get("version",""); print(v) if v else sys.exit(1)'
}

# advisor_fingerprint [<fingerprint>]
#
# This node's identity fingerprint in the eleven numbered groups the Advisor
# shows, to read out group by group or paste into its compare box.
advisor_fingerprint()
{
    local fp=$1

    if [ -z "$fp" ] ; then
        if [ ! -x /usr/local/bin/cube-advisor-agent ] ; then
            echo "Error: the Advisor agent is not installed on this node" >&2
            return 1
        fi
        fp=$(/usr/local/bin/cube-advisor-agent status 2>/dev/null | awk '/^Fingerprint:/ { sub(/^Fingerprint: */, "") ; print ; exit }')
        if [ -z "$fp" ] ; then
            echo "Error: this node holds no Advisor identity; enrol first" >&2
            return 1
        fi
    fi
    FP="$fp" python3 -c '
import os
fp = os.environ["FP"].strip()
body = fp[len("SHA256:"):] if fp.startswith("SHA256:") else fp
print("Fingerprint: " + fp)
groups = [body[i:i+4] for i in range(0, len(body), 4)]
print("  " + "  ".join("%d %s" % (n + 1, g) for n, g in enumerate(groups)))
'
}

# advisor_url
#
# The Advisor this node enrolled with. Nodes enrolled before the URL was
# recorded reach the same host the tunnel dials, on the default HTTPS port.
advisor_url()
{
    if [ -r "$ADVISOR_URL_FILE" ] ; then
        cat "$ADVISOR_URL_FILE"
        return 0
    fi
    local host
    host=$(cut -d: -f1 "$ADVISOR_IDENTITY_DIR/server" 2>/dev/null)
    [ -n "$host" ] || return 1
    echo "https://$host"
}

# advisor_installed_version -- the agent binary on this node, or nothing.
advisor_installed_version()
{
    [ -x /usr/local/bin/cube-advisor-agent ] || return 1
    /usr/local/bin/cube-advisor-agent version 2>/dev/null | awk '{ print $2 ; exit }'
}

# advisor_update_notice
#
# One line when the Advisor's current release is newer than what runs here.
# Read by `advisor status` and the health check; changes nothing.
advisor_update_notice()
{
    local installed current
    installed=$(advisor_installed_version) || return 0
    current=$(cat "$ADVISOR_CURRENT_RELEASE_FILE" 2>/dev/null)
    [ -n "$current" ] && [ "$current" != "$installed" ] || return 0
    echo "A newer Advisor agent is available: $current (this node runs $installed). Run 'advisor upgrade' to install it."
}

# advisor_upgrade [force]
#
# Installs the Advisor's current release on every enrolled node: each fetches
# over its own identity on the tunnel port (no token, same fingerprint),
# verifies against the image's key, installs, restarts.
advisor_upgrade()
{
    local force=${1:-} node rc=0 any=0

    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        remote_run $node stat "$ADVISOR_AGENT_CERT" >/dev/null 2>&1 || continue
        any=1
        echo "== $node"
        remote_run $node "$HEX_SDK advisor_upgrade_node $force" 2>&1 | sed 's/^/   /' || rc=1
    done
    if [ $any -eq 0 ] ; then
        echo "Error: no node of this cluster is enrolled; run 'advisor enroll' first" >&2
        return 1
    fi
    return $rc
}

# advisor_upgrade_node [force] -- this node only; advisor_upgrade fans it out.
advisor_upgrade_node()
{
    local force=${1:-} base installed current arch artifact tmp out ca

    if [ ! -r "$ADVISOR_AGENT_CERT" ] || [ ! -r "$ADVISOR_AGENT_KEY" ] ; then
        echo "Error: this node is not enrolled; run 'advisor enroll' first" >&2
        return 1
    fi
    # The tunnel address: the listener that verifies our certificate, whose
    # own certificate is signed by the enrolment CA the agent pinned at enrol.
    base="https://$(cat "$ADVISOR_IDENTITY_DIR/server" 2>/dev/null)"
    ca="$ADVISOR_IDENTITY_DIR/enrollment-ca.crt"
    [ "$base" != "https://" ] && [ -r "$ca" ] || {
        echo "Error: this node has no tunnel address or enrolment CA on record; re-enrol" >&2
        return 1
    }
    installed=$(advisor_installed_version)

    out=$(curl -fsS --max-time 30 --cacert "$ca" --cert "$ADVISOR_AGENT_CERT" --key "$ADVISOR_AGENT_KEY" \
            "$base/api/v1/releases/current") || {
        echo "Error: the Advisor at $base did not name a current release" >&2
        return 1
    }
    current=$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version",""))')
    if [ -z "$current" ] ; then
        echo "Error: the Advisor named no release" >&2
        return 1
    fi
    if [ "$current" = "$installed" ] && [ "$force" != force ] ; then
        echo "Already current: $installed"
        return 0
    fi

    arch=$(advisor_agent_arch) || return 1
    artifact="cube-advisor-agent_linux_$arch"
    tmp=$(mktemp -d /run/advisor-release.XXXXXX) || return 1
    trap 'rm -rf "$tmp"' RETURN

    local f
    for f in "$ADVISOR_MANIFEST_NAME" "$ADVISOR_SIGNATURE_NAME" "$artifact" ; do
        curl -fsS --max-time 120 --cacert "$ca" --cert "$ADVISOR_AGENT_CERT" --key "$ADVISOR_AGENT_KEY" \
             -o "$tmp/$f" "$base/api/v1/releases/$current/$f" || {
            echo "Error: cannot fetch $f for $current from $base" >&2
            return 1
        }
    done

    # Verification before anything is installed or executed, as at enrol.
    advisor_install_release "$tmp" "$artifact" /usr/local/bin/cube-advisor-agent || return 1
    advisor_agent_service_start
    echo "Upgraded the Advisor agent: ${installed:-none} -> $current"
}

# advisor_enroll_peers [force]
#
# From an enrolled node: fetch a node token over this node's certificate and
# enrol every node that has no identity yet. Each peer gets its own identity
# and prints its own fingerprint to verify; console access follows this node.
advisor_enroll_peers()
{
    local force=${1:-} base ca console=false tok node rc=0 todo=()

    if [ ! -r "$ADVISOR_AGENT_CERT" ] || [ ! -r "$ADVISOR_AGENT_KEY" ] ; then
        echo "Error: this node is not enrolled; paste a token from the Advisor to enrol it first" >&2
        return 1
    fi
    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        [ "$node" = "$HOSTNAME" ] && continue
        if [ -n "$force" ] || ! remote_run $node stat "$ADVISOR_AGENT_CERT" >/dev/null 2>&1 ; then
            todo+=("$node")
        fi
    done
    if [ "${#todo[@]}" -eq 0 ] ; then
        echo "Every node of this cluster is already enrolled."
        return 0
    fi

    base="https://$(cat "$ADVISOR_IDENTITY_DIR/server" 2>/dev/null)"
    ca="$ADVISOR_IDENTITY_DIR/enrollment-ca.crt"
    [ "$base" != "https://" ] && [ -r "$ca" ] || {
        echo "Error: this node has no tunnel address or enrolment CA on record; re-enrol" >&2
        return 1
    }
    [ -r "$ADVISOR_CONSOLE_CA" ] && console=true
    tok=$(curl -fsS --max-time 30 --cacert "$ca" --cert "$ADVISOR_AGENT_CERT" --key "$ADVISOR_AGENT_KEY" \
            -H 'Content-Type: application/json' -d "{\"console_access\":$console}" \
            "$base/api/v1/node-tokens" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])') || {
        echo "Error: the Advisor refused to issue a node token to this node (is its identity verified?)" >&2
        return 1
    }

    echo "Enrolling ${#todo[@]} node(s): ${todo[*]}"
    for node in "${todo[@]}" ; do
        echo "== $node"
        # The token travels over the cluster's own ssh and lands in a root-only
        # file the peer removes when done; never an argument, never in ps.
        if ! printf '%s\n' "$tok" | remote_run $node "umask 077 && mkdir -p /run/advisor-peer && cat > /run/advisor-peer/token" ; then
            echo "   Error: could not deliver the token to $node" >&2 ; rc=1 ; continue
        fi
        remote_run $node "$HEX_SDK advisor_enroll_token /run/advisor-peer/token '' $force; rc=\$?; rm -f /run/advisor-peer/token; exit \$rc" 2>&1 | sed 's/^/   /' || rc=1
    done
    [ $rc -eq 0 ] && echo "Verify each new node on the Advisor's enrolment page: its fingerprint is printed above."
    return $rc
}

advisor_enroll_token()
{
    local token_file=$1 version=${2:-} force=${3:-} dir rc

    if [ -z "$token_file" ] ; then
        echo "Error: advisor_enroll_token: usage <token-file> [<version>] [force]" >&2
        return 1
    fi
    if [ ! -r "$token_file" ] ; then
        echo "Error: cannot read the token file: $token_file" >&2
        return 1
    fi

    dir=$(mktemp -d /run/advisor-token.XXXXXX) || return 1
    # The secret and the certificate land here; do not leave either behind.
    trap 'rm -rf "$dir"' RETURN

    if ! _advisor_token_decode "$(cat "$token_file")" "$dir" ; then
        echo "Error: that does not look like an Advisor enrolment token" >&2
        return 1
    fi

    local server ca_file=""
    server=$(cat "$dir/url")
    [ -r "$dir/ca" ] && ca_file="$dir/ca"
    _advisor_write_file "$ADVISOR_URL_FILE" "$server" || return 1

    # The token names the service, not the agent: which build pairs with the
    # service changes after the token is issued, so the service is asked.
    if [ -z "$version" ] ; then
        advisor_trust_ca "$ca_file" || return 1
        version=$(advisor_current_release "$server" "$dir/secret") || {
            echo "Error: the Advisor did not name an agent release; pass a version explicitly" >&2
            return 1
        }
        echo "Advisor's current agent release: $version"
    fi

    # The issuer's action level and consent are written before the agent is
    # started, so the one restart in advisor_enroll picks them up — level_set
    # and consent_set each restart the agent, and three restarts in a row is
    # what made enrolment look stuck. Validated the same way those commands do.
    local level consent
    if [ -r "$dir/level" ] ; then
        level=$(cat "$dir/level")
        case "$level" in
            observe|operate|internal) _advisor_write_file "$ADVISOR_LEVEL_FILE" "$level" || return 1 ;;
            *) echo "Error: the token names an unknown action level '$level'" >&2 ; return 1 ;;
        esac
    fi
    if [ -r "$dir/consent" ] ; then
        consent=$(cat "$dir/consent")
        case "$consent" in
            always|destructive|never) _advisor_write_file "$ADVISOR_CONSENT_FILE" "$consent" || return 1 ;;
            *) echo "Error: the token names an unknown consent setting '$consent'" >&2 ; return 1 ;;
        esac
    fi

    advisor_enroll "$server" "$dir/secret" "$version" "$ca_file" "$force"
    rc=$?
    [ $rc -eq 0 ] || return $rc

    # The agent writes the dials the Advisor actually serves this cluster at
    # (its record, not the token) once it has enrolled; report those.
    level=$(head -n1 "$ADVISOR_LEVEL_FILE" 2>/dev/null | tr -d '[:space:]')
    consent=$(head -n1 "$ADVISOR_CONSENT_FILE" 2>/dev/null | tr -d '[:space:]')
    [ -n "$level" ]   && echo "action level: $level"
    [ -n "$consent" ] && echo "consent: $consent"

    # Console access was decided when the token was issued; say what this node
    # was granted rather than leaving the operator to infer it. The Advisor
    # hands its console CA back with the identity (agent 0.4.14); a node that
    # was granted console access trusts it here, so nothing is carried by hand.
    if [ "$(cat "$dir/console")" = true ] ; then
        if [ -r "$ADVISOR_IDENTITY_DIR/console-ca.pub" ] ; then
            advisor_console_trust "$ADVISOR_IDENTITY_DIR/console-ca.pub" || \
                echo "Warning: console access was granted but this node could not trust the Advisor's console CA; see the journal, then re-run enroll" >&2
        else
            echo "console access: granted, but this Advisor does not send its console CA (it predates agent 0.4.14); upgrade the Advisor and re-run enroll" >&2
        fi
        echo "console access: enabled for this cluster"
    else
        echo "console access: not granted"
    fi
}

advisor_enroll()
{
    local server=$1 token_file=$2 version=$3 ca_file=${4:-} force=${5:-}
    local arch artifact tmp rc

    if [ -z "$server" ] || [ -z "$token_file" ] || [ -z "$version" ] ; then
        echo "Error: advisor_enroll: usage <server> <token-file> <version>" >&2
        return 1
    fi
    if [ ! -r "$token_file" ] ; then
        echo "Error: cannot read the pairing token file: $token_file" >&2
        return 1
    fi

    # Before anything reaches the network: the fetch below and the agent that
    # follows both verify against the system store.
    advisor_trust_ca "$ca_file" || return 1

    # Enrolment is a cluster-level act, and the agent's tools are the control
    # plane's: cluster check, the CLI, the cube-cos-api reads. A compute or
    # storage node can neither answer those nor speak for the cluster, so it
    # must not hold the cluster's identity.
    if ! is_control_node ; then
        echo "Error: enrol from a control node; this node's role is ${T_cubesys_role:-unknown}" >&2
        return 1
    fi

    local cluster
    cluster=$(advisor_cluster_id) || return 1
    arch=$(advisor_agent_arch) || return 1
    artifact="cube-advisor-agent_linux_$arch"

    tmp=$(mktemp -d /run/advisor-release.XXXXXX) || return 1
    # The download directory holds no secrets, but it does hold a binary that is
    # about to be trusted; do not leave it lying around either way.
    trap 'rm -rf "$tmp"' RETURN

    local url="$server/api/v1/releases/$version"
    local f
    for f in "$ADVISOR_MANIFEST_NAME" "$ADVISOR_SIGNATURE_NAME" "$artifact" ; do
        if ! curl -fsS --max-time 120 \
                -H "Authorization: Bearer $(cat "$token_file")" \
                -o "$tmp/$f" "$url/$f" ; then
            echo "Error: cannot fetch $f from $url" >&2
            return 1
        fi
    done

    # Verification happens before anything is installed or executed, which is
    # the entire point of the chain: the artifact is untrusted until the image's
    # own public key says otherwise.
    advisor_install_release "$tmp" "$artifact" /usr/local/bin/cube-advisor-agent || return 1

    # A rebuilt Advisor signs with a new CA, leaving every identity
    # valid-looking and useless. The agent will not replace one unasked, so
    # forcing stays the operator's word, never a retry.
    local force_arg=""
    [ -n "$force" ] && force_arg="-force"
    /usr/local/bin/cube-advisor-agent enroll \
        -server "$server" -token-file "$token_file" -cluster "$cluster" $force_arg
    rc=$?
    case $rc in
        0)
            # What the operator reads to the Advisor's screen, in the groups it shows.
            advisor_fingerprint
            advisor_agent_service_start
            advisor_targets_init || echo "Warning: could not seed $ADVISOR_TARGETS_FILE; add the cube-cos target by hand" >&2
            # Carries a report this node already has (a re-enrolment). A first
            # enrolment has none -- the Advisor tells only an agent it admits,
            # and admission waits for the fingerprint to be verified;
            # health_advisor_check picks that one up.
            advisor_sso_report_apply || \
                echo "Warning: could not apply the Advisor's console origins; run 'hex_cli -c advisor sso_origins' to check" >&2
            # CMP may already be installed; if so its ingress is reachable
            # from the moment this cluster enrols. Same module, called
            # directly (only cross-module calls route through $HEX_SDK).
            advisor_targets_discover
            ;;
        3) echo "This node is already enrolled; nothing was changed." >&2
           echo "If the Advisor was rebuilt, this node's identity was signed by a CA that no longer exists; re-run with the force argument to replace it." >&2 ;;
        4) echo "The pairing token was refused -- ask for a fresh one." >&2 ;;
        5) echo "The Advisor service was unreachable from this node." >&2 ;;
        *) echo "Error: enrolment failed (exit $rc)" >&2 ;;
    esac
    return $rc
}
