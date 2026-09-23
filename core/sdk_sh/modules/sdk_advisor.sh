# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# Node-side helpers for the Cube AI Advisor agent.
#
# The agent is released by Bigstack as signed per-arch artifacts and must be
# verified before a node executes one. Two decisions from ADR 0003 shape what is
# here:
#
#   * Verification lives in cubecos, not in the agent's own repository. A
#     verifier must not share a build pipeline with the artifact it verifies, or
#     one compromised pipeline produces both.
#   * The trust anchor belongs to the OS, and is compiled into hex_config the
#     same way hex compiles in the licence key -- so it is deliberately NOT
#     configurable from here. A verifier whose trust anchor is chosen by its
#     caller verifies nothing.
#
# The check itself is in hex_config rather than in this file. Key and check
# belong in one place: this file lives under /usr/lib/hex_sdk where root can
# edit it, so a shell verifier could have its check removed while the compiled-in
# key stayed perfectly safe -- which protects the wrong half.
#
# A customer who would rather not trust our binary can still do the whole check
# with standard tools, because the manifest is in sha256sum's own format:
#
#     hex_config advisor_pubkey > release.pub
#     openssl dgst -sha256 -verify release.pub -signature manifest.txt.sig manifest.txt
#     sha256sum -c manifest.txt

ADVISOR_TRUST_ANCHOR=/etc/pki/ca-trust/source/anchors/cube-advisor.crt
# The identity an enrolled node holds. config_advisor.cpp names the same paths
# (it decides from them whether the agent should run and migrates them across
# an upgrade); repeated here because hex_sdk cannot read the C header.
ADVISOR_IDENTITY_DIR=/etc/cube/advisor-agent
ADVISOR_AGENT_CERT=$ADVISOR_IDENTITY_DIR/agent.crt
# The action level and consent dial this cluster serves (ADR 0011/0017). Files
# in the agent's own directory, read by the agent at startup and authoritative
# there -- the SaaS's mirror is only a hint. These are the paths an operator
# sets them through; a name absent means the fail-closed default (observe /
# always). The agent's own ParseLevel/ParseConsent own the vocabulary; the two
# lists below are kept in step with them by hand.
ADVISOR_LEVEL_FILE=$ADVISOR_IDENTITY_DIR/action-level
ADVISOR_CONSENT_FILE=$ADVISOR_IDENTITY_DIR/consent
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

# The node-local allowlist the agent will dial through the tunnel: symbolic
# name -> routing address. The Advisor only ever holds name -> what the
# upstream calls itself; this file is the other half, and only this file, so
# one name can route to the management network and another to the provider
# network without the Advisor ever learning either address. A name missing
# here is a name the agent refuses to dial -- this file is the operator's
# control over what we can reach, not ours, so nothing here repairs it.
ADVISOR_TARGETS_FILE=/etc/cube-advisor-agent/web-targets.json

# The targets discovery found installed on this cluster: "name host:port", one
# per line. The agent runs on every node and reads its own allowlist, but only
# a node holding the app framework's kubeconfig can see what is installed; this
# file is how the node that can see it tells the nodes that cannot. Only this
# set ever crosses a node boundary: each node's own hex_config commit turns it
# into allowlist entries.
#
# The set, not an address: an address alone cannot say whether CMP is installed
# behind it, and the ingress exists from the app framework's install onwards --
# which is before CMP is installed, not after.
ADVISOR_DISCOVERED_FILE=/etc/cube-advisor-agent/discovered-targets

# The Advisor console origins whose Skyline WebSSO callbacks keystone should
# trust, one URL per line. Supplied by whoever knows how the Advisor spells its
# origins -- the installer, or an operator -- because the node cannot derive
# them. config_advisor.cpp migrates this file; the two files below are rebuilt
# from it by advisor_sso_apply and so are not migrated.
ADVISOR_SSO_ORIGINS_FILE=/etc/cube-advisor-agent/sso-origins
# What the Advisor itself reported, propagated to every control node. The
# operator record above is an additional allowance on top of this, never a
# replacement: both are deliberate acts, and advisor_sso_apply trusts their
# union. Kept apart so the Advisor's half can be withdrawn the moment it stops
# reporting an origin without taking an operator's entry with it.
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
# Keycloak's own admin console refuses to finish loading on an origin its
# client does not list: the session-check iframe answers 403 and the UI spins
# forever. The client is Keycloak's built-in, not one of the four this
# cluster's terraform declares, so adding an origin here is not fought by the
# next apply.
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
# Verifies the release in <dir>: the manifest's signature against the key
# compiled into this image, then every artifact digest the manifest lists. When
# <artifact> is given, it must additionally be one the manifest names.
#
# Returns 0 only when every check passes. Every other outcome is a refusal.
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
# Prints the version recorded in a release manifest. Reads a comment line, so it
# must only ever be called on a manifest that advisor_verify_release has already
# accepted — otherwise it is reporting whatever an attacker wrote.
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
# Start the tunnel now. Enrolment leaves the node holding a valid certificate;
# without this it would hold one and never connect, which looks from the
# Advisor exactly like a broken tunnel.
#
# Started, never enabled: in cubecos hex_config owns when a service runs (the
# advisor module's Commit calls SystemdCommitService), so an enable symlink
# would make systemd a second owner, starting the agent at multi-user.target on
# a node hex_config had decided should not be running it.
advisor_agent_service_start()
{
    if [ ! -r "$ADVISOR_AGENT_UNIT" ] ; then
        echo "Warning: $ADVISOR_AGENT_UNIT is missing; the tunnel cannot be started" >&2
        return 0
    fi

    if systemctl start "$ADVISOR_AGENT_UNIT_NAME" >/dev/null 2>&1 ; then
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
# The cluster's identity for enrolment -- this cluster's, never this node's.
# The Advisor makes it the certificate's common name and the primary key five
# of its tables reference, none with ON UPDATE CASCADE, so it is chosen once
# and effectively permanently. Two sources, in order:
#
#   1. CUBE_CLUSTER_ID, written by cube-cos-driver at deploy time. Derived from
#      the cluster UUID the driver assigns, so it is unique by construction --
#      and the Advisor's fleet then shows the same id the driver shows.
#   2. cubesys.controller, the operator-chosen controller name: the VIP's name
#      on an HA cluster and the single node's name otherwise. Identical on
#      every node of the cluster, so enrolling from any control node yields
#      one identity -- but a name, so two sites can collide on it.
#
# Never the hostname: a 3-node cluster would then enrol as whichever node the
# operator happened to type the command on.
advisor_cluster_id()
{
    local id=""

    if [ -r /etc/cube/phone-home-agent.env ] ; then
        id=$(sed -n 's/^CUBE_CLUSTER_ID=//p' /etc/cube/phone-home-agent.env | head -1)
    fi
    if [ -z "$id" ] ; then
        id=$(source /usr/sbin/hex_tuning /etc/settings.txt 2>/dev/null ; echo "${T_cubesys_controller:-}")
    fi
    # An enrolled node already carries the answer in its own certificate, and
    # that certificate is migrated across a firmware upgrade while the two
    # sources above are not: phone-home-agent.env is written at deployment and
    # does not survive, and cubesys.controller is absent on a converged
    # single-node cluster. Both gone leaves an enrolled node unable to say
    # which cluster it is -- so read back what it was enrolled as.
    #
    # Last, not first: the two above describe the cluster this node belongs to
    # now, while the certificate records what it enrolled as once.
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
# Maps this machine to the artifact naming the release manifest uses. Unknown
# architectures are a refusal rather than a guess: installing the wrong binary
# fails later and less clearly than not installing one.
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
# The same shape advisor_targets_set enforces, checked silently: these lines
# come from discovery and from a file discovery wrote, not from an operator
# typing, so there is no one here to hand a specific message to.
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
# Writes one of the agent's node-local files atomically: a temp file in the
# same directory, then mv. The agent can read these at any moment, so a
# reader must never see half of a write.
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
# Records on this node the set of targets discovery found installed. Called on
# every node by advisor_targets_discover, so it must be reachable through
# hex_sdk. Replaces the file outright: the argument list is the whole answer,
# and a target that is no longer named is no longer discovered.
#
# Records only what was found; what it becomes is advisor_targets_init's
# business, on the node itself.
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
# Prints the recorded set, one "name host:port" pair per line. Silent when the
# file is absent: a cluster with no app framework is the normal case, not a
# fault. Every line's shape is rechecked, so a hand-edited file can never turn
# into a malformed allowlist entry.
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
# Seeds the allowlist on a node that has none: cube-cos, which every node can
# name for itself, plus exactly what discovery recorded on this node
# (advisor_discovered_set). cube-cos always, because every node serves it
# locally whatever else is installed.
#
# Seeds, never reconciles. A file that is already there is left exactly as it
# is -- an operator who removed a target removed it on purpose, and a helper
# that puts it back turns "delete one line to revoke access" into "delete one
# line and wait for it to return".
# advisor_dashboard_address
#
# Where this cluster's own web UI answers: the control VIP on an HA cluster,
# this node's management address otherwise.
#
# Not 127.0.0.1:8080: that port is httpd, which answers 403 to everything.
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
# The targets every node can name for itself, one "<name> <host:port>" per
# line: this cluster's dashboard, and the endpoints the dashboard links out to
# on other ports of the same address -- Keycloak, Skyline and the Ceph
# dashboard.
#
# Each needs allowing in its own right: the dashboard builds those URLs in
# script from the bare cluster address, so a proxy never sees them to rewrite.
advisor_own_targets()
{
    local dash addr

    dash=$(advisor_dashboard_address) || return 1
    addr="${dash%:*}"
    echo "cube-cos $dash"
    echo "cube-cos-idp $addr:10443"
    echo "cube-cos-skyline $addr:9999"
    echo "cube-cos-ceph $addr:7443"
    # Skyline's federated login leaves Skyline: the browser is sent to
    # keystone's public endpoint and then to the SAML service provider mellon
    # hosts. Both are the Advisor's companions of cube-cos-skyline -- one
    # session, one cookie jar -- but the agent still dials each by name, so
    # each needs allowing in its own right.
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
# Prints the current allowlist, one "name host:port" pair per line. This file
# is hand-edited -- an operator's editor, jq, python -m json.tool all
# reformat it -- so it is read with jq rather than a regex that only
# understands the exact layout this module happens to write. Silent, not an
# error, if the file has not been seeded yet.
advisor_targets_list()
{
    [ -r "$ADVISOR_TARGETS_FILE" ] || return 0
    jq -r 'to_entries[] | "\(.key) \(.value)"' "$ADVISOR_TARGETS_FILE" 2>/dev/null
}

# advisor_targets_set <name> <host:port>
#
# Adds an entry, or replaces one by the same name. Validated here because the
# agent dials whatever this file says: a malformed name or address is refused
# where the message can still help someone, not left for the tunnel to fail
# on later.
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

    # -e turns a file that will not parse as a JSON object into a refusal
    # instead of "start from nothing" -- the difference between an
    # operator's edit and this quietly emptying the allowlist under them. A
    # file jq cannot even see, such as a genuinely empty one, still has to be
    # caught by hand: jq runs its filter zero times over zero input values
    # and calls that success.
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
# Makes a level or consent change take effect. The agent reads both files once,
# at startup, so a running agent must be restarted; a stopped one picks the file
# up on its next start, so its absence is not an error. Restart rather than
# reload: the agent has no reload path for these, and a bounced tunnel
# reconnects on its own.
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
# Records the action level this cluster serves (ADR 0011). Written to the file
# the agent reads as authoritative, so the value the executor enforces and the
# value an operator set are one thing. The vocabulary is the agent's; a word
# outside it is refused here rather than written for the agent to reject later.
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
# Records how much this cluster asks a person before the agent acts (ADR 0011,
# amended). Same custody as the level: the file the agent reads, the vocabulary
# the agent owns.
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
# Prints the level and consent this node serves, one per line as "<field>
# <value>". An absent file reads as the fail-closed default the agent would use,
# named so an operator sees what is in force rather than a blank.
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
# Publishes to the whole cluster the set of web targets that are actually
# installed on it.
#
# This runs where the kubeconfig is -- one node -- but the agent runs on every
# node and dials from every node, so every node needs the set. It is written
# out with remote_run over CUBE_NODE_LIST_HOSTNAMES, the same fan-out
# health_advisor_check uses. Only the set travels: each node's own hex_config
# commit turns it into allowlist entries, so no node ever writes another
# node's allowlist.
#
# What exists is decided per target from its Helm release, not from the
# ingress: the ingress is created by the app framework's own install, which
# happens before CMP is installed, so an address proves the framework is there
# and says nothing about CMP. A release is the honest answer, and it is one a
# namespace or an HTTP probe during an install is not.
#
# Both names sit at that one address on purpose -- the portal and its identity
# provider must share one origin or the OIDC state cookie is set on one and
# the callback lands on the other.
#
# Callers are the installers (app_framework_install, app_import) and enrolment.
# Idempotent, and each call declares only what it finds, so calling it from
# every one of them is right: whichever ran last is the cluster's current
# answer.
#
# On this node it also sets the names outright, so the node that just enrolled
# or just installed CMP does not wait for its next commit -- and that
# deliberately brings a name back if an operator has unset it here. Not the
# never-repair rule being broken: never-repair stops a *startup* silently
# restoring a file someone edited, while this only runs from an install or
# enrolment event that is itself declaring the endpoint again.
# _advisor_discard_kubeconfig <path>
#
# Removes a kubeconfig advisor_targets_discover fetched, and unsets the export
# so a later call in the same shell fetches a fresh one. A no-op for the empty
# path, which is what a caller-supplied APPFW_KUBECONFIG leaves behind.
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

    # A cluster that never enrolled must not gain an allowlist as a side
    # effect of installing CMP.
    #
    # The fan-out above is deliberately on this side of that guard. An install
    # normally runs long before anyone enrols, so the set has to be on every
    # node by then: enrolment's own advisor_targets_init reads this file and
    # seeds from it, which is the only way a cluster that installed CMP first
    # ends up with cube-cmp in its allowlist at all.
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
# A WebSSO callback URL this node will let keystone post a token to. Checked
# hard because that is exactly what the entry authorises: keystone substitutes
# the matched origin into sso_callback_template.html as the form action, so a
# line here is "send an unscoped token to this URL", not a display string.
#
# https only, no userinfo, no query or fragment, and "*" allowed only in the
# host -- the same shape keystone's patched _origin_matches will compare.
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
    # strings are handed to a remote shell by advisor_sso_origins_set_cluster,
    # and a callback path has no need of a quote, a space or a metacharacter.
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

# advisor_sso_origins_set <url> [<url> ...]
#
# Records the Advisor console origins whose WebSSO callbacks keystone should
# trust, replacing whatever was recorded before.
#
# Supplied, never derived. In address mode the origin is an address out of the
# Advisor's own pool and in domain mode it is <target>--<session>.<domain>;
# neither is anything this node can work out from what it knows, and guessing
# wrong here would mean trusting a host nobody chose. A node told nothing
# trusts nothing extra, and Skyline still logs in with Keystone Credentials.
advisor_sso_origins_set()
{
    local url content="" nl='
'

    [ $# -ge 1 ] || { echo "Error: advisor_sso_origins_set: usage <url> [<url> ...]" >&2 ; return 1 ; }
    for url in "$@" ; do
        if ! _advisor_sso_origin_valid "$url" ; then
            echo "Error: not an https origin URL without userinfo, query or fragment: $url" >&2
            return 1
        fi
        content="$content${content:+$nl}$url"
    done

    _advisor_write_file "$ADVISOR_SSO_ORIGINS_FILE" "$content"
}

# advisor_sso_origins_list
#
# Prints the recorded origins, one per line. Every line is rechecked: this file
# migrates across a firmware upgrade, so what it held on the old partition is
# not automatically what this release considers well formed.
advisor_sso_origins_list()
{
    local line

    [ -r "$ADVISOR_SSO_ORIGINS_FILE" ] || return 0
    while read -r line ; do
        case $line in ''|'#'*) continue ;; esac
        _advisor_sso_origin_valid "$line" || continue
        echo "$line"
    done < "$ADVISOR_SSO_ORIGINS_FILE"
}

# advisor_sso_origins_clear
advisor_sso_origins_clear()
{
    rm -f "$ADVISOR_SSO_ORIGINS_FILE"
}

# advisor_sso_origins_set_cluster <url> [<url> ...]
#
# The same, on every node, and applied there.
#
# Cluster-wide because keystone is: a WebSSO callback arrives at the control
# VIP and haproxy hands it to whichever control node it likes, so a list that
# is only on the node an operator typed it on makes the login succeed or fail
# by which backend answered. Unlike the dial allowlist, which is deliberately
# each node's own veto, this is one fact about the Advisor.
#
# Validated here first, so a bad URL is refused once rather than partly
# applied across the cluster.
advisor_sso_origins_set_cluster()
{
    local url node args="" rc=0

    [ $# -ge 1 ] || { echo "Error: advisor_sso_origins_set_cluster: usage <url> [<url> ...]" >&2 ; return 1 ; }
    for url in "$@" ; do
        if ! _advisor_sso_origin_valid "$url" ; then
            echo "Error: not an https origin URL without userinfo, query or fragment: $url" >&2
            return 1
        fi
        # _advisor_sso_origin_valid admits no quote, space or metacharacter,
        # so the URL survives the remote shell as one word.
        args="$args '$url'"
    done

    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! remote_run "$node" "$HEX_SDK advisor_sso_origins_set$args && $HEX_SDK advisor_sso_apply" >/dev/null 2>&1 ; then
            echo "Warning: could not record the Advisor console origins on $node; Skyline federated login will fail whenever that node answers" >&2
            rc=1
        fi
    done
    return $rc
}

# advisor_sso_origins_clear_cluster
#
# Withdraws the trust everywhere it was granted. A node missed here keeps
# trusting an origin the operator revoked, which is the direction that matters.
advisor_sso_origins_clear_cluster()
{
    local node rc=0

    for node in "${CUBE_NODE_LIST_HOSTNAMES[@]}" ; do
        if ! remote_run "$node" "$HEX_SDK advisor_sso_origins_clear && $HEX_SDK advisor_sso_apply" >/dev/null 2>&1 ; then
            echo "Error: could not withdraw the Advisor console origins on $node; it still trusts them" >&2
            rc=1
        fi
    done
    return $rc
}

# _advisor_sso_base_valid <origin-base>
#
# "https://host[:port]" and nothing more: no path, because a base is what a
# consumer appends its own path to. The host may carry "*" where a mode puts
# the session id in the hostname.
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
# What the Advisor reported, one "<target> <origin-base>" per line.
#
# The raw report is what travels, not a URL composed from it. Three things
# consume this and each needs a different part: keystone wants Skyline's
# callback URL, mellon wants hostnames without ports, and Keycloak wants the
# identity provider's origin with its port. Composing one of those at the
# sending end left the other two with nothing to work from.
#
# Every line is rechecked: this file crosses a node boundary and a firmware
# upgrade.
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
# The Advisor's half of what keystone should trust: Skyline's callback URL,
# composed from its reported base. A base carrying a session wildcard is kept
# as it is -- keystone's patched matcher globs the host, which is the only form
# that can name a per-session origin at all.
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
# What is actually trusted: the Advisor's report and the operator's record,
# deduplicated. The Advisor's half is the live truth and withdraws itself; the
# operator's half is an explicit act and only an operator removes it.
advisor_sso_effective_list()
{
    { advisor_sso_reported_list ; advisor_sso_origins_list ; } | awk '!seen[$0]++'
}

# advisor_sso_origins_show
#
# What is trusted and where each entry came from. Two sources behave
# differently -- one withdraws itself, the other does not -- so an operator
# deciding whether to clear something has to be able to tell them apart.
advisor_sso_origins_show()
{
    local url reported

    reported=$(advisor_sso_reported_list)
    advisor_sso_effective_list | while read -r url ; do
        if echo "$reported" | grep -qxF "$url" ; then
            echo "$url (reported by the Advisor)"
        else
            echo "$url (declared here)"
        fi
    done
}

# advisor_sso_report_read
#
# The agent's report, as "<target> <origin-base>" lines this release accepts.
# Passed on whole rather than reduced to one composed URL: see
# advisor_sso_reported_bases for why every consumer needs a different part.
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
# What the agent's report turns into, cluster-wide. Run from a systemd path
# unit watching the agent's file, so a console the Advisor re-addressed takes
# effect without waiting for the next hex_config commit.
#
# Propagated rather than read in place: the agent only runs on enrolled nodes,
# while keystone answers on every control node behind the VIP.
advisor_sso_report_apply()
{
    local node word args="" rc=0

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
# An admin token for the local Keycloak, from the password terraform already
# keeps. Printed on stdout; empty on any failure, and every caller treats that
# as "leave Keycloak alone" rather than as something to retry.
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
# Lets Keycloak's admin console load on the Advisor's console origins.
#
# Its client lists the origins a browser may run it from, derived from redirect
# URIs that are relative to this cluster's own address. The Advisor's origin
# cannot be derived from anything, so the session-check iframe is refused with
# a 403 and the UI never finishes loading -- the same shape as keystone's
# trusted_dashboard, in a different component's allowlist.
#
# Idempotent, and careful about removal: it takes away only origins it added
# before, recorded in ADVISOR_SSO_KEYCLOAK_STATE, so withdrawing a console
# origin withdraws this too while an operator's own entries are left alone.
# Best effort throughout -- a Keycloak that cannot be reached must not fail a
# commit, and the next one tries again.
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
# Regenerates the two files that make Skyline's WebSSO work through the
# console, from the recorded origins, and applies them only when they changed.
#
# Both are derived, so neither is migrated: the first commit on a new firmware
# slot rebuilds them from the record, which is.
#
#   keystone   cube_mellon_wsgi.py merges this into trusted_dashboard at import.
#              keystone.conf cannot carry it -- config_keystone.cpp owns
#              [federation] and rewrites it every commit.
#   mellon     a later <Location /v3> block wins the MellonRedirectDomains
#              merge, so the Advisor's origin can be added without editing
#              v3_mellon_keycloak_master.conf, which keystone_idp recreates
#              from its .def on every commit of its own.
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
# True when writing <content> to <path> would change it, counting "should not
# exist" as empty content. Restarting keystone on every commit would drop every
# federated login in progress, so the comparison is the point, not an
# optimisation.
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
# The whole node-side install path: fetch the release, verify it against the
# image's public key, install the agent, then enrol this cluster.
#
# The token is read from a file rather than an argument. A pairing token on a
# command line is visible in ps to every user on the box for as long as the
# process runs, and this function is exactly the place that would otherwise
# leak it.
#
# Every step fails closed. A partial install -- a verified binary with no
# identity, or an identity with no binary -- is worse than a clean failure the
# operator can retry.
# advisor_trust_ca <ca-file>
#
# Installs the Advisor's CA into this node's system trust store.
#
# Enrolment fetches the release over HTTPS with curl and then runs the agent,
# which talks to the same endpoint through Go's TLS. Both read the system store
# and neither takes a CA path, so an Advisor serving its own certificate -- the
# normal case offline, where there is no public CA to lean on -- fails the fetch
# with "self-signed certificate" and nothing after it runs. Passing -k instead
# is not an option: the pairing token is a bearer credential on that request.
#
# Deliberately not migrated across a firmware upgrade. This is enrolment-time
# trust; the tunnel's own trust is the enrollment CA the agent pins from its
# identity directory, which is migrated. Verified on hardware: after an upgrade
# that dropped this anchor, the agent reconnected on its own.
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
# Makes this node accept console certificates the Advisor mints.
#
# A console session is piped to this node's own sshd, so sshd is what decides
# whether a certificate is good -- the Advisor only signs. Nothing pushes the
# CA here: the Advisor prints it at install time and an operator installs it,
# which is the same shape as trusting its TLS CA at enrolment.
#
# Both files are in config_advisor.cpp's migrate list, so once installed they
# survive a firmware upgrade without being reinstalled.
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

    # An Advisor that has been rebuilt signs with a new enrollment CA, which
    # leaves every node holding an identity signed by one that no longer
    # exists -- valid-looking, and useless. The agent refuses to replace an
    # existing identity without being told to, correctly, so forcing has to be
    # something the operator asks for rather than a retry that silently
    # discards a working identity.
    local force_arg=""
    [ -n "$force" ] && force_arg="-force"
    /usr/local/bin/cube-advisor-agent enroll \
        -server "$server" -token-file "$token_file" -cluster "$cluster" $force_arg
    rc=$?
    case $rc in
        0)
            advisor_agent_service_start
            advisor_targets_init || echo "Warning: could not seed $ADVISOR_TARGETS_FILE; add the cube-cos target by hand" >&2
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
