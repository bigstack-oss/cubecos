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
        id=$(source /usr/sbin/hex_tuning /etc/settings.txt 2>/dev/null ; echo "$T_cubesys_controller")
    fi
    if [ -z "$id" ] ; then
        echo "Error: cannot tell which cluster this node belongs to (no CUBE_CLUSTER_ID, no cubesys.controller)" >&2
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
advisor_targets_init()
{
    local discovered

    [ -e "$ADVISOR_TARGETS_FILE" ] && return 0

    # awk, not a read loop: a loop on the right of a pipe runs in a subshell
    # and would leave the string it built behind in it.
    discovered=$(advisor_discovered_list | awk '{ printf ",\"%s\":\"%s\"", $1, $2 }')
    _advisor_targets_write "{\"cube-cos\":\"127.0.0.1:8080\"$discovered}"
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
advisor_enroll()
{
    local server=$1 token_file=$2 version=$3
    local arch artifact tmp rc

    if [ -z "$server" ] || [ -z "$token_file" ] || [ -z "$version" ] ; then
        echo "Error: advisor_enroll: usage <server> <token-file> <version>" >&2
        return 1
    fi
    if [ ! -r "$token_file" ] ; then
        echo "Error: cannot read the pairing token file: $token_file" >&2
        return 1
    fi

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

    /usr/local/bin/cube-advisor-agent enroll \
        -server "$server" -token-file "$token_file" -cluster "$cluster"
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
        3) echo "This node is already enrolled; nothing was changed." >&2 ;;
        4) echo "The pairing token was refused -- ask for a fresh one." >&2 ;;
        5) echo "The Advisor service was unreachable from this node." >&2 ;;
        *) echo "Error: enrolment failed (exit $rc)" >&2 ;;
    esac
    return $rc
}
