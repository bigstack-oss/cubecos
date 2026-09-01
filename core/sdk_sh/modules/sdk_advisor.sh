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
# image. Enabled only once a node has enrolled -- see advisor_agent_service_enable.
ADVISOR_AGENT_UNIT_NAME=cube-advisor-agent.service
ADVISOR_AGENT_UNIT=/usr/lib/systemd/system/$ADVISOR_AGENT_UNIT_NAME

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

# advisor_agent_service_enable
#
# Start the tunnel and keep it started. Enrolment leaves the node holding a
# valid certificate; without this it would hold one and never connect, which
# looks from the Advisor exactly like a broken tunnel.
#
# Enabled here rather than at image build: an un-enrolled node has no identity,
# so the unit would crash-loop from first boot until someone enrolled it.
advisor_agent_service_enable()
{
    if [ ! -r "$ADVISOR_AGENT_UNIT" ] ; then
        echo "Warning: $ADVISOR_AGENT_UNIT is missing; the tunnel will not start on its own" >&2
        return 0
    fi

    systemctl daemon-reload
    if systemctl enable --now "$ADVISOR_AGENT_UNIT_NAME" >/dev/null 2>&1 ; then
        echo "Tunnel service enabled; the agent will reconnect on its own after a reboot."
    else
        # The identity is saved and enrolment did succeed, so this must not
        # fail the command -- say what is wrong and let the operator start it.
        echo "Warning: could not enable $ADVISOR_AGENT_UNIT_NAME; start it manually with: systemctl enable --now $ADVISOR_AGENT_UNIT_NAME" >&2
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

    # CLUSTER_ENV is overridable so the unit test can supply a file; nothing
    # in production sets it.
    local env_file=${CLUSTER_ENV:-/etc/cube/phone-home-agent.env}
    if [ -r "$env_file" ] ; then
        id=$(sed -n 's/^CUBE_CLUSTER_ID=//p' "$env_file" | head -1)
    fi
    if [ -z "$id" ] ; then
        id=$(source /usr/sbin/hex_tuning /etc/settings.txt 2>/dev/null ; echo "$T_cubesys_controller")
    fi
    if [ -z "$id" ] ; then
        echo "Error: cannot tell which cluster this node belongs to (no CUBE_CLUSTER_ID, no cubesys.controller)" >&2
        return 1
    fi

    # The Advisor folds this to lowercase and stores the folded form, so case
    # is not an error here either -- cubesys.controller is declared with
    # ValidateRegex/DFT_REGEX_STR ("^.*$"), which constrains nothing, and a
    # cluster whose controller is named Controller01 is perfectly legal. Fold
    # to match what will be stored, then refuse only the shapes that genuinely
    # break a certificate CN, a URL path segment or /etc/hosts. The Advisor
    # enforces the same set with a CHECK constraint; refusing here first means
    # the operator sees the rule before a round trip, not a remote error after.
    id=$(echo "$id" | tr '[:upper:]' '[:lower:]')
    case $id in
        *[!a-z0-9._-]*)
            echo "Error: cluster id may contain only letters, digits, '.', '-' and '_': $id" >&2
            return 1 ;;
        [!a-z0-9]*|*[!a-z0-9])
            echo "Error: cluster id must start and end with a letter or digit: $id" >&2
            return 1 ;;
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
        0) advisor_agent_service_enable ;;
        3) echo "This node is already enrolled; nothing was changed." >&2 ;;
        4) echo "The pairing token was refused -- ask for a fresh one." >&2 ;;
        5) echo "The Advisor service was unreachable from this node." >&2 ;;
        *) echo "Error: enrolment failed (exit $rc)" >&2 ;;
    esac
    return $rc
}
