#!/bin/bash
# Operator-run acceptance script for a tenant volume tier change end to end.
# This script creates and destroys real resources on a real cluster.
# Requires two Cinder backends to be registered.
#
# Usage: test_tier_change_e2e.sh <DEST_TIER> [DRY_RUN=1 for testing without cluster]
# Example: test_tier_change_e2e.sh SSD
# Example (dry-run): DRY_RUN=1 test_tier_change_e2e.sh SSD

set -e

# Configuration
DEST_TIER="${1:-}"
LOG_FILE="/tmp/tier_change_e2e_$(date +%s).log"
DRY_RUN="${DRY_RUN:-0}"

# Volume and VM names
VOL_NAME="tier-e2e-$(date +%s | tail -c 6)"
VM_NAME="tier-e2e-vm-$(date +%s | tail -c 6)"
TEST_SIZE=2  # GiB
TEST_PATTERN=0xCD
TEST_DATA_SIZE=64M  # 64 MiB pattern

# Track resources for cleanup
CREATED_VOL_ID=""
CREATED_VM_ID=""
CREATED_SNAPSHOT_ID=""

# Migration signal tracking
VOL_INITIAL_STATUS=""
VOL_INITIAL_TYPE=""
VOL_INITIAL_MIG_STATUS=""
VOL_FINAL_STATUS=""
VOL_FINAL_TYPE=""
VOL_FINAL_MIG_STATUS=""
VOL_STATUS_SETTLED_TIME=""
VOL_TYPE_CHANGED_TIME=""
VOL_MIG_STATUS_COMPLETE_TIME=""

trap cleanup EXIT

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE"
}

fail() {
    log_error "$*"
    exit 1
}

# Stub commands for dry-run mode
if [ "$DRY_RUN" = "1" ]; then
    DRY_RUN_MARKER="/tmp/dryrun_marker_$$"
    openstack() {
        case "$1" in
            "volume")
                case "$2" in
                    "create")
                        echo "vol-dryrun-12345"
                        ;;
                    "show")
                        # Check for -f value -c <field> pattern
                        if [ "$4" = "-f" ] && [ "$5" = "value" ] && [ "$6" = "-c" ]; then
                            case "$7" in
                                "volume_type")
                                    # Simulate type change: first query returns CubeStorage, subsequent return SSD
                                    if [ ! -f "$DRY_RUN_MARKER" ]; then
                                        touch "$DRY_RUN_MARKER"
                                        echo "CubeStorage"
                                    else
                                        echo "SSD"
                                    fi
                                    ;;
                                "status")
                                    echo "in-use"
                                    ;;
                                *)
                                    return 127
                                    ;;
                            esac
                        else
                            # Full show output for grepping
                            cat <<'EOF'
| Property                             | Value                                |
| os-vol-mig-status-attr:migration_status | success                           |
| status                               | in-use                             |
| volume_type                          | SSD                                |
EOF
                        fi
                        ;;
                    "delete")
                        return 0
                        ;;
                    "snapshot")
                        case "$3" in
                            "create")
                                echo "snap-dryrun-11111"
                                touch "/tmp/dryrun_has_snapshot_$$"
                                ;;
                            "delete")
                                rm -f "/tmp/dryrun_has_snapshot_$$"
                                return 0
                                ;;
                        esac
                        ;;
                    "type")
                        if [ "$3" = "list" ]; then
                            echo "CubeStorage"
                            echo "SSD"
                        fi
                        ;;
                esac
                ;;
            "server")
                case "$2" in
                    "create")
                        echo "vm-dryrun-67890"
                        ;;
                    "show")
                        if [ "$4" = "-f" ] && [ "$5" = "value" ] && [ "$6" = "-c" ]; then
                            case "$7" in
                                "status")
                                    echo "ACTIVE"
                                    ;;
                                *)
                                    return 127
                                    ;;
                            esac
                        else
                            echo "ACTIVE"
                        fi
                        ;;
                    "add")
                        return 0
                        ;;
                    "remove")
                        return 0
                        ;;
                    "stop")
                        touch "/tmp/dryrun_vm_stopped_$$"
                        return 0
                        ;;
                    "start")
                        rm -f "/tmp/dryrun_vm_stopped_$$"
                        return 0
                        ;;
                    "delete")
                        return 0
                        ;;
                esac
                ;;
        esac
    }
    qemu-io() {
        return 0
    }
    rbd() {
        case "$1" in
            "ls")
                return 0
                ;;
            *)
                return 127
                ;;
        esac
    }
    hex_sdk() {
        case "$1" in
            "cinder_move_preflight")
                # Return E_VM_NOT_RUNNING if VM is stopped, E_HAS_SNAPSHOTS if snapshot exists
                if [ -f "/tmp/dryrun_vm_stopped_$$" ]; then
                    echo '{"ok":false,"code":"E_VM_NOT_RUNNING","reason":"VM not running","blockers":[{"code":"E_VM_NOT_RUNNING","reason":"VM is not running"}]}'
                    return 1
                elif [ -f "/tmp/dryrun_has_snapshot_$$" ]; then
                    echo '{"ok":false,"code":"E_HAS_SNAPSHOTS","reason":"Volume has snapshots","blockers":[{"code":"E_HAS_SNAPSHOTS","reason":"Volume has one or more snapshots"}]}'
                    return 1
                else
                    echo '{"ok":true,"code":"OK","reason":"ok","blockers":[],"src_type":"CubeStorage","dst_type":"SSD","size_gb":2,"attached_to":"vm-dryrun-67890"}'
                    return 0
                fi
                ;;
            "cinder_move_volume")
                echo '{"ok":true,"code":"OK","reason":"ok","dispatched":true}'
                return 0
                ;;
            "cinder_volume_image_name")
                echo "volume-$2"
                return 0
                ;;
            *)
                return 127
                ;;
        esac
    }
    hex_cli() {
        if [ "$1" = "-c" ] && [ "$2" = "cluster" ] && [ "$3" = "-c" ] && [ "$4" = "check" ]; then
            echo "Storage  ok "
            echo "Compute  ok "
            return 0
        else
            return 127
        fi
    }
fi

cleanup() {
    exit_code=$?
    log "=== Cleanup phase ==="

    # Detach volume from VM
    if [ -n "$CREATED_VOL_ID" ] && [ -n "$CREATED_VM_ID" ]; then
        log "Detaching volume $CREATED_VOL_ID from VM $CREATED_VM_ID..."
        openstack server remove volume "$CREATED_VM_ID" "$CREATED_VOL_ID" 2>/dev/null || true
        sleep 5
    fi

    # Delete the snapshot
    if [ -n "$CREATED_SNAPSHOT_ID" ]; then
        log "Deleting snapshot $CREATED_SNAPSHOT_ID..."
        openstack volume snapshot delete "$CREATED_SNAPSHOT_ID" 2>/dev/null || true
        sleep 2
    fi

    # Delete the VM
    if [ -n "$CREATED_VM_ID" ]; then
        log "Deleting VM $CREATED_VM_ID..."
        openstack server delete "$CREATED_VM_ID" 2>/dev/null || true
        sleep 10
    fi

    # Delete the volume
    if [ -n "$CREATED_VOL_ID" ]; then
        log "Deleting volume $CREATED_VOL_ID..."
        openstack volume delete "$CREATED_VOL_ID" 2>/dev/null || true
        sleep 5
    fi

    log "Cleanup complete"

    # Final cluster health check
    log "=== Final cluster health check ==="
    health_output=$(hex_cli -c cluster -c check 2>&1 || true)
    not_ok=$(echo "$health_output" | grep -v ' ok ' || true)
    if [ -n "$not_ok" ]; then
        log_error "Cluster health check found issues:"
        echo "$not_ok" | tee -a "$LOG_FILE"
    else
        log "Cluster health check: all services ok"
    fi

    exit $exit_code
}

# Validate parameters
[ -n "$DEST_TIER" ] || fail "DEST_TIER parameter required (e.g., SSD)"

log "=== Starting acceptance run ==="
SOURCE_TIER="CubeStorage"
log "Source tier: $SOURCE_TIER"
log "Destination tier: $DEST_TIER"
log "Test volume size: ${TEST_SIZE} GiB"
log "Test pattern size: $TEST_DATA_SIZE"
log "Log file: $LOG_FILE"
[ "$DRY_RUN" = "1" ] && log "DRY_RUN mode enabled - external commands stubbed"

# Step 1: Create the volume
log "=== Step 1: Creating volume ==="
CREATED_VOL_ID=$(openstack volume create --type CubeStorage --size "$TEST_SIZE" "$VOL_NAME" -f value -c id | tr -d "[:space:]")
[ -n "$CREATED_VOL_ID" ] || fail "Failed to create volume"
log "Volume created: $CREATED_VOL_ID"
sleep 10

# Step 2: Write pattern to the volume
log "=== Step 2: Writing test pattern to volume ==="
qemu-io -f raw -c "write -P $TEST_PATTERN 0 $TEST_DATA_SIZE" "rbd:cinder-volumes/volume-$CREATED_VOL_ID" 2>&1 | tee -a "$LOG_FILE" || fail "Failed to write pattern to volume"
log "Pattern written successfully"

# Step 3: Create VM and attach volume
log "=== Step 3: Creating VM and attaching volume ==="
CREATED_VM_ID=$(openstack server create --image Cirros --flavor lr.small --network resizespine --wait "$VM_NAME" -f value -c id | tr -d "[:space:]")
[ -n "$CREATED_VM_ID" ] || fail "Failed to create VM"
log "VM created: $CREATED_VM_ID"
sleep 5

openstack server add volume "$CREATED_VM_ID" "$CREATED_VOL_ID"
log "Volume attached to VM"
sleep 20

# Step 4: Run preflight check
log "=== Step 4: Running preflight check ==="
pf_output=$(hex_sdk cinder_move_preflight "$CREATED_VOL_ID" "$DEST_TIER")
log "Preflight output: $pf_output"

pf_ok=$(echo "$pf_output" | jq -r '.ok // false')
[ "$pf_ok" = "true" ] || fail "Preflight returned ok:false"
log "Preflight check passed (ok:true)"

# Step 5: Dispatch the move
log "=== Step 5: Dispatching volume move ==="
move_output=$(hex_sdk cinder_move_volume "$CREATED_VOL_ID" "$DEST_TIER")
log "Move dispatch output: $move_output"

dispatched=$(echo "$move_output" | jq -r '.dispatched // false')
[ "$dispatched" = "true" ] || fail "Move dispatch failed"
log "Move dispatched successfully"

# Record initial state after move dispatch
VOL_INITIAL_TYPE=$(openstack volume show "$CREATED_VOL_ID" -f value -c type)
VOL_INITIAL_STATUS=$(openstack volume show "$CREATED_VOL_ID" -f value -c status)
VOL_INITIAL_MIG_STATUS=$(openstack volume show "$CREATED_VOL_ID" 2>&1 | awk -F'|' '/os-vol-mig-status-attr:migration_status/{print $3}' | tr -d ' ' || echo "UNAVAILABLE")
log "Initial state - type:$VOL_INITIAL_TYPE status:$VOL_INITIAL_STATUS migration_status:$VOL_INITIAL_MIG_STATUS"

# Step 6: Wait for migration completion - both status settlement AND type change
log "=== Step 6: Waiting for migration completion (status+type) ==="
max_wait=600
if [ "$DRY_RUN" = "1" ]; then
    max_wait=20
fi
elapsed=0
type_changed=0
status_settled=0

while [ $elapsed -lt $max_wait ]; do
    VOL_FINAL_TYPE=$(openstack volume show "$CREATED_VOL_ID" -f value -c type)
    VOL_FINAL_STATUS=$(openstack volume show "$CREATED_VOL_ID" -f value -c status)
    VOL_FINAL_MIG_STATUS=$(openstack volume show "$CREATED_VOL_ID" 2>&1 | awk -F'|' '/os-vol-mig-status-attr:migration_status/{print $3}' | tr -d ' ' || echo "UNAVAILABLE")

    # Check if type has changed
    if [ "$type_changed" = "0" ] && [ "$VOL_FINAL_TYPE" != "$VOL_INITIAL_TYPE" ]; then
        type_changed=1
        VOL_TYPE_CHANGED_TIME="$elapsed seconds"
        log "Type changed at $VOL_TYPE_CHANGED_TIME: $VOL_INITIAL_TYPE -> $VOL_FINAL_TYPE"
    fi

    # Check if status is settled (not in retyping/migrating states)
    if [ "$status_settled" = "0" ]; then
        case "$VOL_FINAL_STATUS" in
            in-use|available)
                status_settled=1
                VOL_STATUS_SETTLED_TIME="$elapsed seconds"
                log "Status settled at $VOL_STATUS_SETTLED_TIME: $VOL_FINAL_STATUS"
                ;;
            *)
                : # Still migrating
                ;;
        esac
    fi

    # Check migration_status signal if available
    if [ "$VOL_FINAL_MIG_STATUS" != "UNAVAILABLE" ] && [ "$VOL_FINAL_MIG_STATUS" = "success" ]; then
        if [ -z "$VOL_MIG_STATUS_COMPLETE_TIME" ]; then
            VOL_MIG_STATUS_COMPLETE_TIME="$elapsed seconds"
            log "Migration status reached 'success' at $VOL_MIG_STATUS_COMPLETE_TIME"
        fi
    fi

    # Both conditions met: proceed
    if [ "$type_changed" = "1" ] && [ "$status_settled" = "1" ]; then
        log "Migration complete: both type changed and status settled"
        break
    fi

    log "Still migrating... type:$VOL_FINAL_TYPE status:$VOL_FINAL_STATUS migration_status:$VOL_FINAL_MIG_STATUS ($elapsed/$max_wait seconds)"
    sleep 10
    elapsed=$((elapsed + 10))
done

[ "$type_changed" = "1" ] || fail "Volume type did not change within $max_wait seconds"
[ "$status_settled" = "1" ] || fail "Volume status did not settle within $max_wait seconds"

log "=== Step 6 Summary: Migration Signals ==="
log "Signal timing - type_changed:$VOL_TYPE_CHANGED_TIME status_settled:$VOL_STATUS_SETTLED_TIME migration_status:$VOL_MIG_STATUS_COMPLETE_TIME"
log "Final state - type:$VOL_FINAL_TYPE status:$VOL_FINAL_STATUS migration_status:$VOL_FINAL_MIG_STATUS"

# Step 7: Record migration_status attribute visibility
log "=== Step 7: Checking migration_status attribute visibility ==="
migration_status=$(openstack volume show "$CREATED_VOL_ID" 2>&1 || true)
if echo "$migration_status" | grep -q "migration_status"; then
    log "FINDING: migration_status attribute IS visible to operator credentials"
else
    log "FINDING: migration_status attribute NOT visible to operator credentials"
fi

# Step 8: Verify data integrity
log "=== Step 8: Verifying data integrity ==="
img_name=$(hex_sdk cinder_volume_image_name "$CREATED_VOL_ID")
log "Resolved image name: $img_name"

# The destination tier has its own pool and its own ceph.conf; read both from the
# storage record rather than assuming the source cluster's defaults.
dest_json=$(hex_sdk cinder_get_storage "{\"name\":\"$DEST_TIER\"}" 2>/dev/null)
dest_pool=$(echo "$dest_json" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(next((k["value"] for k in d["storage"]["service"]["driverSection"] if k["key"]=="rbd_pool"), ""))' 2>/dev/null)
dest_conf=$(echo "$dest_json" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(next((k["value"] for k in d["storage"]["service"]["driverSection"] if k["key"]=="rbd_ceph_conf"), ""))' 2>/dev/null)
[ -n "$dest_pool" ] || fail "could not resolve the destination pool for $DEST_TIER"
[ -n "$dest_conf" ] || fail "could not resolve the destination ceph.conf for $DEST_TIER"
log "Destination pool: $dest_pool (conf: $dest_conf)"

# Read WITHOUT a pipe so the exit status is qemu-io's own, not tee's.
log "Reading pattern from destination cluster..."
read_out=$(qemu-io -f raw -r -c "read -P $TEST_PATTERN 0 $TEST_DATA_SIZE" \
    "rbd:${dest_pool}/${img_name}:conf=${dest_conf}" 2>&1)
read_rc=$?
echo "$read_out" >> "$LOG_FILE"
[ $read_rc -eq 0 ] || fail "destination read failed (rc=$read_rc): $read_out"
log "Data integrity verified on destination ($TEST_DATA_SIZE of pattern $TEST_PATTERN)"

# Verify image is gone from source
log "Verifying image removed from source..."
if rbd ls cinder-volumes | grep -q "^volume-$CREATED_VOL_ID\$"; then
    fail "Source image still exists: volume-$CREATED_VOL_ID"
fi
log "Source image confirmed removed"

# Step 9: Verify VM is still ACTIVE
log "=== Step 9: Verifying VM status ==="
vm_status=$(openstack server show "$CREATED_VM_ID" -f value -c status)
[ "$vm_status" = "ACTIVE" ] || fail "VM status is $vm_status, expected ACTIVE"
log "VM status confirmed: ACTIVE"

# Step 10: Test refusal paths
log "=== Step 10: Testing refusal paths ==="

# Test: Stop the instance, preflight should refuse
log "Testing E_VM_NOT_RUNNING refusal..."
openstack server stop "$CREATED_VM_ID"
sleep 10

# the volume now sits on DEST_TIER, so the refusal probe must aim back at the source
refusal_output=$(hex_sdk cinder_move_preflight "$CREATED_VOL_ID" "$SOURCE_TIER" 2>&1 || true)
log "Refusal output (stopped VM): $refusal_output"

refusal_code=$(echo "$refusal_output" | jq -r '.code // ""')
[ "$refusal_code" = "E_VM_NOT_RUNNING" ] || fail "Expected E_VM_NOT_RUNNING but got: $refusal_code"

blockers=$(echo "$refusal_output" | jq -r '.blockers // []' | jq length)
[ "$blockers" -gt 0 ] || fail "Expected blockers array but it is empty"
log "Refusal path E_VM_NOT_RUNNING verified with $blockers blockers"

# Restart VM for next test
openstack server start "$CREATED_VM_ID"
sleep 10

# Test: Snapshot a detached volume, preflight should refuse
log "Testing E_HAS_SNAPSHOTS refusal..."
openstack server remove volume "$CREATED_VM_ID" "$CREATED_VOL_ID"
sleep 5

CREATED_SNAPSHOT_ID=$(openstack volume snapshot create --volume "$CREATED_VOL_ID" "tier-e2e-snap" -f value -c id)
log "Snapshot created: $CREATED_SNAPSHOT_ID"
sleep 5

refusal_output=$(hex_sdk cinder_move_preflight "$CREATED_VOL_ID" "$SOURCE_TIER" 2>&1 || true)
log "Refusal output (has snapshots): $refusal_output"

refusal_code=$(echo "$refusal_output" | jq -r '.code // ""')
[ "$refusal_code" = "E_HAS_SNAPSHOTS" ] || fail "Expected E_HAS_SNAPSHOTS but got: $refusal_code"

blockers=$(echo "$refusal_output" | jq -r '.blockers // []' | jq length)
[ "$blockers" -gt 0 ] || fail "Expected blockers array but it is empty"
log "Refusal path E_HAS_SNAPSHOTS verified with $blockers blockers"

log "=== Acceptance run complete ==="
log "All checks passed"
