#!/bin/bash
#
# hex_cli's `iaas volume move` must consult `hex_sdk cinder_move_preflight`
# (Task 1) before dispatching `cinder retype`, and must print every reason
# the preflight refused -- not just fail silently.
#
# cli_iaas_volume.cpp invokes hex_sdk, openstack and cinder by ABSOLUTE path
# (HEX_SDK -> /usr/sbin/hex_sdk, OPENSTACK_CLI -> /usr/bin/openstack,
# and a literal "/usr/bin/cinder"), so stubs on $PATH are never consulted --
# they must be installed at those exact paths. Domain/project validation and
# the volume/volume-type lookups (getVolumes, getVolumeTypes,
# GetVolumeTypeById) all go through those absolute-path binaries before the
# command ever reaches the preflight call, so all three must be stubbed for
# the CLI to get that far.
#
# hex_cli is not installed on this host and a freshly built one cannot run
# here (built for centos9; missing libreadline.so.8). It DOES run inside the
# centos9-jail build jail, so this test must run there, as root, against the
# hex_cli built from this worktree.
#
#   Run (inside the jail): bash core/sdk_sh/tests/test_cinder_move_cli_guard.sh <path-to-hex_cli>
#
set -u

HEX_CLI_BIN="${1:-/root/workspace/centos9-jail-sdd/core/main/hex_cli}"

if [ "$(id -u)" != "0" ]; then
    echo "this test must run as root (it installs stubs at /usr/sbin and /usr/bin, and writes /etc/appliance/state)" >&2
    exit 1
fi
if [ ! -x "$HEX_CLI_BIN" ]; then
    echo "hex_cli binary not found/executable at $HEX_CLI_BIN" >&2
    exit 1
fi

FAILED=0
chk() { # description, actual, expected
    if [ "$2" = "$3" ]; then
        printf '%-46s -> PASS\n' "$1"
    else
        printf '%-46s -> FAIL (got %s, want %s)\n' "$1" "$2" "$3"
        FAILED=1
    fi
}
chk_bool() { # description, condition (0 = pass)
    if [ "$2" -eq 0 ]; then
        printf '%-46s -> PASS\n' "$1"
    else
        printf '%-46s -> FAIL\n' "$1"
        FAILED=1
    fi
}

T=$(mktemp -d)
DISPATCH_MARK=$T/cli_guard_dispatch
STATE_DIR=/etc/appliance/state
CONFIGURED_FILE=$STATE_DIR/configured
COMMIT_FILE=/run/cube_commit_done

# --- back up any real binaries/state at the absolute paths we stub, so the
# jail is left as we found it ---
declare -A BACKED_UP
for f in /usr/sbin/hex_sdk /usr/bin/openstack /usr/bin/cinder; do
    if [ -e "$f" ]; then
        mv "$f" "$f.pre-cli-guard-test"
        BACKED_UP[$f]=1
    fi
done
HAD_CONFIGURED=0
[ -e "$CONFIGURED_FILE" ] && HAD_CONFIGURED=1
HAD_COMMIT=0
[ -e "$COMMIT_FILE" ] && HAD_COMMIT=1

cleanup() {
    rm -f /usr/sbin/hex_sdk /usr/bin/openstack /usr/bin/cinder
    for f in /usr/sbin/hex_sdk /usr/bin/openstack /usr/bin/cinder; do
        [ -n "${BACKED_UP[$f]:-}" ] && mv "$f.pre-cli-guard-test" "$f"
    done
    [ "$HAD_CONFIGURED" -eq 0 ] && rm -f "$CONFIGURED_FILE"
    [ "$HAD_COMMIT" -eq 0 ] && rm -f "$COMMIT_FILE"
    rm -rf "$T"
}
trap cleanup EXIT

# --- CLI mode registration for `iaas volume` is gated (at process static-init
# time, before main() even runs) on !HexStrictIsErrorState() &&
# !FirstTimeSetupRequired() && CubeSysCommitAll(). Satisfy those with the same
# sentinel files hex_cli itself checks, so the mode is actually reachable. ---
mkdir -p "$STATE_DIR"
touch "$CONFIGURED_FILE"     # FirstTimeSetupRequired() -> false
touch "$COMMIT_FILE"         # CubeSysCommitAll() -> true
rm -f "$STATE_DIR/strict_mode_error"   # HexStrictIsErrorState() -> false

# --- stub hex_sdk: domain/project lookups (so CliMatchCmdHelper matches the
# fixed argv below) and cinder_move_preflight (Task 1's interface) ---
cat > /usr/sbin/hex_sdk <<EOF
#!/bin/bash
case "\$1" in
  os_list_domain_basic) echo "Default" ;;
  os_list_project_by_domain_basic) echo "admin" ;;
  cinder_move_preflight)
    cat <<'JSON'
{"ok":false,"code":"E_HAS_SNAPSHOTS","reason":"volume must not have snapshots","blockers":[{"code":"E_HAS_SNAPSHOTS","reason":"volume must not have snapshots"},{"code":"E_VM_NOT_RUNNING","reason":"the attached instance must be running or paused"}],"src_type":"ceph","dst_type":"tier-nvme","size_gb":10,"attached_to":"i-1"}
JSON
    exit 1
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x /usr/sbin/hex_sdk

# --- stub openstack: getVolumes / getVolumeTypes / GetVolumeTypeById, all
# called (via OpenstackExec, absolute path) before the CLI reaches the
# preflight -- must resolve "v1" as a real volume of type "ceph" and
# "tier-nvme" as a real, different destination type ---
cat > /usr/bin/openstack <<EOF
#!/bin/bash
case "\$1 \$2" in
  "volume list") echo '[{"ID":"v1","Name":"vol1"}]' ;;
  "volume type") echo '[{"Name":"tier-nvme"},{"Name":"ceph"}]' ;;
  "volume show") echo '{"type":"ceph"}' ;;
  *) echo '[]' ;;
esac
EOF
chmod +x /usr/bin/openstack

# --- stub cinder: only records that it was invoked; retype must never reach it ---
cat > /usr/bin/cinder <<EOF
#!/bin/bash
echo "RETYPE DISPATCHED \$@" >> "$DISPATCH_MARK"
EOF
chmod +x /usr/bin/cinder

rm -f "$DISPATCH_MARK"

# --- drive the CLI non-interactively with all four positional args:
# <domain> <project> <volume_id> <destination_volume_type> ---
OUT=$("$HEX_CLI_BIN" -c iaas -c volume -c move -c default -c admin -c v1 -c tier-nvme 2>&1)
EXIT_CODE=$?

echo "$OUT" > "$T/out"
echo "---- hex_cli output ----"
cat "$T/out"
echo "---- exit code: $EXIT_CODE ----"

grep -q "must not have snapshots" "$T/out"
chk_bool "reason 1 (E_HAS_SNAPSHOTS) printed" $?

grep -q "must be running or paused" "$T/out"
chk_bool "reason 2 (E_VM_NOT_RUNNING) printed" $?

if [ -f "$DISPATCH_MARK" ]; then
    chk_bool "cinder retype NOT dispatched" 1
else
    chk_bool "cinder retype NOT dispatched" 0
fi

# Note: hex_cli's non-interactive "-c" mode (RunCommand called with
# forkCmd=false from main()) discards the CommandResult and main() always
# `return 0`, regardless of CLI_SUCCESS/CLI_FAILURE -- this is pre-existing
# hex_cli behavior, not something this change affects. So the process exit
# code cannot be used to detect the refusal; only the output text and the
# absence of a cinder dispatch can. Exit code is printed above for reference.

if [ "$FAILED" -ne 0 ]; then
    echo "FAILED"
    exit 1
fi
echo "ALL PASS"
exit 0
