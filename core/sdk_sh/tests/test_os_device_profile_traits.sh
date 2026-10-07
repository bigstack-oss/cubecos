#!/bin/bash
#
# Unit test for ../modules/sdk_os.sh:
#   os_device_profile_current -- does an existing profile ask for what
#                                os_device_profile_groups_for builds today
#   os_device_profile_remove  -- delete a profile by name, through its uuid
#   os_nova_pgpu_host_list_by_instance_id
#                             -- hosts with PGPU providers carrying the traits
#                                the instance's profile requires
#
# All three exist because of #1478: cyborg's nvidia driver reports a pgpu as one
# CUSTOM_NVIDIA_<PID> trait since Antelope, where Yoga reported the pair
# CUSTOM_GPU_NVIDIA + CUSTOM_GPU_PRODUCT_ID_<PID>. Profiles created against the
# old pair keep their name -- and so stay in use -- unless something checks
# them, and the host list used to read the pair back out by field ordinal.
#
# Self-contained: `openstack` and `mariadb` are stubbed, no Cyborg needed.
# Needs bash 4 (the host list uses associative arrays).
#   Run: bash test_os_device_profile_traits.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_os.sh"
for fn in os_device_profile_groups_for os_device_profile_current os_device_profile_remove \
          os_nova_pgpu_host_list_by_instance_id ; do
    eval "$(awk "/^$fn\\(\\)/{f=1} f{print} f&&/^}/{exit}" "$SRC")"
    [ "$(type -t $fn)" = function ] || { echo "FAIL: $fn not extracted"; exit 1; }
done
eval "$(declare -f os_nova_pgpu_host_list_by_instance_id | sed 's#/usr/bin/mariadb#fake_mariadb#')"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

LOGFILE="$TMP/log"; : > "$LOGFILE"
log_error() { printf '%s\n' "$1" >> "$LOGFILE"; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

# The shape `openstack accelerator device profile list -f json` prints, taken
# from cn13 (3.2.0, cyborg 14.1.0) on 2026-10-07: the resource count comes back
# as a string, not the integer the profile was created with.
OLD_DP='{"uuid": "uuid-old", "name": "rtx_pro_6000_blackwell_server_edition_1", "description": null,
         "groups": [{"resources:PGPU": "1", "trait:CUSTOM_GPU_PRODUCT_ID_2BB5": "required", "trait:CUSTOM_GPU_NVIDIA": "required"}]}'
NEW_DP='{"uuid": "uuid-new", "name": "rtx_a2000_1", "description": null,
         "groups": [{"resources:PGPU": "1", "trait:CUSTOM_NVIDIA_2531": "required"}]}'
TWO_DP='{"uuid": "uuid-two", "name": "rtx_a2000_2", "description": null,
         "groups": [{"resources:PGPU": "1", "trait:CUSTOM_NVIDIA_2531": "required"},
                    {"resources:PGPU": "1", "trait:CUSTOM_NVIDIA_2531": "required"}]}'

DP_JSON="[$OLD_DP, $NEW_DP, $TWO_DP]" DP_LIST_RC=0 DP_DELETE_RC=0
ARQS="" CANDIDATES="" ORIG_HOST=""
CALLS="$TMP/calls"; : > "$CALLS"
fake_openstack() {
    case "$*" in
        "accelerator device profile list -f json")
            [ "$DP_LIST_RC" = 0 ] || { echo "Unable to establish connection" >&2; return "$DP_LIST_RC"; }
            printf '%s' "$DP_JSON" ;;
        "accelerator device profile delete "*)
            printf '%s\n' "$*" >> "$CALLS"
            [ "$DP_DELETE_RC" = 0 ] || { echo "Failed to delete device_profile $5: 500" >&2; return "$DP_DELETE_RC"; } ;;
        "accelerator arq list "*) printf '%s\n' "$ARQS" ;;
        "server show "*" -c OS-EXT-SRV-ATTR:hypervisor_hostname -f value") printf '%s\n' "$ORIG_HOST" ;;
        "allocation candidate list "*) printf '%s\n' "$CANDIDATES" ;;
        *) echo "unexpected: openstack $*" >&2; return 99 ;;
    esac
}
OPENSTACK=fake_openstack

# rp uuid -> placement resource_providers.name, which is <host>_<pci addr>.
declare -A RP_NAME=([rp-a]=cn14_0000:3b:00.0 [rp-b]=cn14_0000:86:00.0 [rp-c]=cn15_0000:3b:00.0
                    [rp-d]=cn16_0000:3b:00.0 [rp-e]=cn13_0001:04:00.0)
fake_mariadb() {
    local rp=$(echo "$*" | sed -n "s/.*uuid='\([^']*\)'.*/\1/p")
    printf 'uuid\tname\n%s\t%s\n' "$rp" "${RP_NAME[$rp]}"
}

# --- 1. os_device_profile_current ---------------------------------------------
os_device_profile_current rtx_a2000_1 2531;   ck "$?" "0" "current: matches today's groups"
os_device_profile_current rtx_a2000_1 2531 1; ck "$?" "0" "current: explicit units=1"
os_device_profile_current rtx_a2000_2 2531 2; ck "$?" "0" "current: units=2, group for group"
os_device_profile_current rtx_pro_6000_blackwell_server_edition_1 2bb5
ck "$?" "1" "stale: the Yoga trait pair cn13 actually has"
os_device_profile_current rtx_a2000_1 2bb5;   ck "$?" "1" "stale: another card's product id"
os_device_profile_current rtx_a2000_2 2531 1; ck "$?" "1" "stale: two groups where one is wanted"

: > "$LOGFILE"
os_device_profile_current nope_1 2531;        ck "$?" "2" "no such profile -> 2, not stale"
ck "$(grep -c 'no device profile named nope_1' "$LOGFILE")" "1" "no such profile -> logged"

: > "$LOGFILE"; DP_LIST_RC=1
os_device_profile_current rtx_a2000_1 2531;   ck "$?" "2" "Cyborg unreachable -> 2, not stale"
ck "$(grep -c 'Unable to establish connection' "$LOGFILE")" "1" "Cyborg unreachable -> its error logged"
DP_LIST_RC=0

# --- 2. os_device_profile_remove ----------------------------------------------
: > "$CALLS"
os_device_profile_remove rtx_pro_6000_blackwell_server_edition_1; ck "$?" "0" "remove: rc"
ck "$(cat "$CALLS")" "accelerator device profile delete uuid-old" "remove: by uuid, the only form the cli takes"

: > "$CALLS"; : > "$LOGFILE"
os_device_profile_remove nope_1;              ck "$?" "1" "remove: no such profile -> non-zero"
ck "$(wc -l < "$CALLS" | tr -d ' ')" "0" "remove: no such profile -> no delete call"

: > "$CALLS"; : > "$LOGFILE"; DP_LIST_RC=1
os_device_profile_remove rtx_a2000_1;         ck "$?" "1" "remove: Cyborg unreachable -> non-zero"
ck "$(wc -l < "$CALLS" | tr -d ' ')" "0" "remove: Cyborg unreachable -> no delete call"
ck "$(grep -c 'Unable to establish connection' "$LOGFILE")" "1" "remove: Cyborg unreachable -> its error logged, not 'no such profile'"
DP_LIST_RC=0

# The foreign key from extended_accelerator_requests makes Cyborg refuse while
# an instance's ARQ still uses the profile.
: > "$LOGFILE"; DP_DELETE_RC=1
os_device_profile_remove rtx_a2000_1;         ck "$?" "1" "remove: refused -> non-zero"
ck "$(grep -c 'rtx_a2000_1 (uuid-new) exited 1: Failed to delete' "$LOGFILE")" "1" "remove: refused -> logged"
DP_DELETE_RC=0

# --- 3. os_nova_pgpu_host_list_by_instance_id ---------------------------------
# Counts hosts with (( hosts[$host]++ )), which set -u rejects on first sight.
set +u

# The instance runs on cn13 with one ARQ from rtx_a2000_1.
ARQS="arq-1 rtx_a2000_1 inst-1"
ORIG_HOST="cn13"
CANDIDATES="rp-a OWNER_CYBORG,CUSTOM_NVIDIA_2531
rp-b OWNER_CYBORG,CUSTOM_NVIDIA_2531
rp-c OWNER_CYBORG,CUSTOM_NVIDIA_2BB5
rp-d OWNER_CYBORG,CUSTOM_NVIDIA_25310
rp-e OWNER_CYBORG,CUSTOM_NVIDIA_2531"

host_list() { os_nova_pgpu_host_list_by_instance_id "$@" | sort | tr '\n' ' '; }

VERBOSE=0
ck "$(host_list inst-1)" "cn14_rp-a " \
   "hosts: cn14 matches, other product (cn15) and the instance's own host (cn13) do not"
ck "$(VERBOSE=1 host_list inst-1)" "cn14 (2 matched GPUs. Picked RPs=rp-a) " \
   "hosts: verbose reports the matched count"

# Whole trait names only: CUSTOM_NVIDIA_2531 must not match CUSTOM_NVIDIA_25310.
ck "$(host_list inst-1 | grep -c cn16)" "0" "hosts: no prefix match"

# Two ARQs -> a host needs two matching providers.
ARQS="arq-1 rtx_a2000_1 inst-1
arq-2 rtx_a2000_1 inst-1"
ck "$(host_list inst-1)" "cn14_rp-a,rp-b " "hosts: two ARQs pick two providers on one host"
ARQS="arq-1 rtx_a2000_1 inst-1"

# A profile from before #1478 asks for both Yoga traits; a provider has to carry
# both, and on Antelope and later none does.
ARQS="arq-1 rtx_pro_6000_blackwell_server_edition_1 inst-2"
ck "$(host_list inst-2)" "" "hosts: Yoga profile matches no Antelope-or-later provider"
CANDIDATES="rp-c OWNER_CYBORG,CUSTOM_GPU_NVIDIA,CUSTOM_GPU_PRODUCT_ID_2BB5
rp-d OWNER_CYBORG,CUSTOM_GPU_NVIDIA"
ck "$(host_list inst-2)" "cn15_rp-c " "hosts: every required trait has to be present"

# The profile behind the ARQ is gone: say so, rather than match every provider.
: > "$LOGFILE"
ARQS="arq-1 deleted_1 inst-3"
out=$(os_nova_pgpu_host_list_by_instance_id inst-3); rc=$?
ck "$rc" "1" "hosts: unknown profile -> non-zero"
ck "$out" "" "hosts: unknown profile -> no hosts"
ck "$(grep -c 'deleted_1 requires no trait' "$LOGFILE")" "1" "hosts: unknown profile -> logged"

# No ARQ -> not a pgpu instance, nothing to say.
ARQS=""
out=$(os_nova_pgpu_host_list_by_instance_id inst-4); rc=$?
ck "$rc" "0" "hosts: no ARQ -> success"
ck "$out" "" "hosts: no ARQ -> no hosts"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
