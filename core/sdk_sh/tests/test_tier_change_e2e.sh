#!/bin/bash
# Operator-run acceptance script for a tenant volume tier change end to end.
# This script creates and destroys real resources on a real cluster.
# Requires two Cinder backends to be registered.
#
# Usage: test_tier_change_e2e.sh <DEST_TIER>
# Example: test_tier_change_e2e.sh SSD

set -e

# Configuration
readonly DEST_TIER="${1:-}"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/tmp/tier_change_e2e_$(date +%s).log"

# Volume and VM names
readonly VOL_NAME="tier-e2e-$(date +%s | tail -c 6)"
readonly VM_NAME="tier-e2e-vm-$(date +%s | tail -c 6)"
readonly TEST_SIZE=2  # GiB
readonly TEST_PATTERN=0xCD
readonly TEST_DATA_SIZE=64M  # 64 MiB pattern

# Track resources for cleanup
CREATED_VOL_ID=""
CREATED_VM_ID=""
CREATED_SNAPSHOT_ID=""

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

cleanup() {
    local exit_code=$?
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
    local health_output
    health_output=$(hex_cli -c cluster -c check 2>&1 || true)
    local not_ok
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
log "Source tier: CubeStorage"
log "Destination tier: $DEST_TIER"
log "Test volume size: ${TEST_SIZE} GiB"
log "Test pattern size: $TEST_DATA_SIZE"
log "Log file: $LOG_FILE"

# Step 1: Create the volume
log "=== Step 1: Creating volume ==="
CREATED_VOL_ID=$(openstack volume create --type CubeStorage --size "$TEST_SIZE" "$VOL_NAME" -f value -c id)
[ -n "$CREATED_VOL_ID" ] || fail "Failed to create volume"
log "Volume created: $CREATED_VOL_ID"
sleep 10

# Step 2: Write pattern to the volume
log "=== Step 2: Writing test pattern to volume ==="
if ! qemu-io -f raw -c "write -P $TEST_PATTERN 0 $TEST_DATA_SIZE" "rbd:cinder-volumes/volume-$CREATED_VOL_ID" 2>&1 | tee -a "$LOG_FILE"; then
    fail "Failed to write pattern to volume"
fi
log "Pattern written successfully"

# Step 3: Create VM and attach volume
log "=== Step 3: Creating VM and attaching volume ==="
CREATED_VM_ID=$(openstack server create --image Cirros --flavor lr.small --network resizespine --wait "$VM_NAME" -f value -c id)
[ -n "$CREATED_VM_ID" ] || fail "Failed to create VM"
log "VM created: $CREATED_VM_ID"
sleep 5

openstack server add volume "$CREATED_VM_ID" "$CREATED_VOL_ID"
[ $? -eq 0 ] || fail "Failed to attach volume to VM"
log "Volume attached to VM"
sleep 20

# Step 4: Run preflight check
log "=== Step 4: Running preflight check ==="
local pf_output
pf_output=$(hex_sdk cinder_move_preflight "$CREATED_VOL_ID" "$DEST_TIER")
log "Preflight output: $pf_output"

local pf_ok
pf_ok=$(echo "$pf_output" | jq -r '.ok // false')
[ "$pf_ok" = "true" ] || fail "Preflight returned ok:false"
log "Preflight check passed (ok:true)"

# Step 5: Dispatch the move
log "=== Step 5: Dispatching volume move ==="
local move_output
move_output=$(hex_sdk cinder_move_volume "$CREATED_VOL_ID" "$DEST_TIER")
log "Move dispatch output: $move_output"

local dispatched
dispatched=$(echo "$move_output" | jq -r '.dispatched // false')
[ "$dispatched" = "true" ] || fail "Move dispatch failed"
log "Move dispatched successfully"

# Step 6: Wait for migration completion
log "=== Step 6: Waiting for migration to complete ==="
local src_type=""
local dst_type=""
local max_wait=600
local elapsed=0

src_type=$(openstack volume show "$CREATED_VOL_ID" -f value -c volume_type)
log "Initial source type: $src_type"

while [ $elapsed -lt $max_wait ]; do
    dst_type=$(openstack volume show "$CREATED_VOL_ID" -f value -c volume_type)
    if [ "$dst_type" != "$src_type" ]; then
        log "Volume type changed to: $dst_type"
        break
    fi
    log "Still migrating... ($elapsed/$max_wait seconds)"
    sleep 10
    elapsed=$((elapsed + 10))
done

[ "$dst_type" != "$src_type" ] || fail "Migration did not complete within $max_wait seconds"
log "Migration completed"

# Step 7: Record migration_status attribute visibility
log "=== Step 7: Checking migration_status attribute visibility ==="
local migration_status
migration_status=$(openstack volume show "$CREATED_VOL_ID" 2>&1 || true)
if echo "$migration_status" | grep -q "migration_status"; then
    log "FINDING: migration_status attribute IS visible to operator credentials"
else
    log "FINDING: migration_status attribute NOT visible to operator credentials"
fi

# Step 8: Verify data integrity
log "=== Step 8: Verifying data integrity ==="
local img_name
img_name=$(hex_sdk cinder_volume_image_name "$CREATED_VOL_ID")
log "Resolved image name: $img_name"

# Verify pattern reads back from destination
log "Reading pattern from destination cluster..."
if ! qemu-io -f raw -c "read -P $TEST_PATTERN 0 $TEST_DATA_SIZE" "rbd:cinder-volumes/$img_name" 2>&1 | tee -a "$LOG_FILE"; then
    fail "Failed to read pattern from destination image or data mismatch"
fi
log "Data integrity verified on destination"

# Verify image is gone from source
log "Verifying image removed from source..."
if rbd ls cinder-volumes | grep -q "^volume-$CREATED_VOL_ID\$"; then
    fail "Source image still exists: volume-$CREATED_VOL_ID"
fi
log "Source image confirmed removed"

# Step 9: Verify VM is still ACTIVE
log "=== Step 9: Verifying VM status ==="
local vm_status
vm_status=$(openstack server show "$CREATED_VM_ID" -f value -c status)
[ "$vm_status" = "ACTIVE" ] || fail "VM status is $vm_status, expected ACTIVE"
log "VM status confirmed: ACTIVE"

# Step 10: Test refusal paths
log "=== Step 10: Testing refusal paths ==="

# Test: Stop the instance, preflight should refuse
log "Testing E_VM_NOT_RUNNING refusal..."
openstack server stop "$CREATED_VM_ID"
sleep 10

local refusal_output
refusal_output=$(hex_sdk cinder_move_preflight "$CREATED_VOL_ID" "$(openstack volume type list -f value -c Name | head -n 1)" 2>&1 || true)
log "Refusal output (stopped VM): $refusal_output"

local refusal_code
refusal_code=$(echo "$refusal_output" | jq -r '.code // ""')
[ "$refusal_code" = "E_VM_NOT_RUNNING" ] || fail "Expected E_VM_NOT_RUNNING but got: $refusal_code"

local blockers
blockers=$(echo "$refusal_output" | jq -r '.blockers // []' | jq length)
[ "$blockers" -gt 0 ] || fail "Expected blockers array but it is empty"
log "Refusal path E_VM_NOT_RUNNING verified with $(jq length <<< "$(echo "$refusal_output" | jq '.blockers')") blockers"

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

refusal_output=$(hex_sdk cinder_move_preflight "$CREATED_VOL_ID" "$(openstack volume type list -f value -c Name | head -n 1)" 2>&1 || true)
log "Refusal output (has snapshots): $refusal_output"

refusal_code=$(echo "$refusal_output" | jq -r '.code // ""')
[ "$refusal_code" = "E_HAS_SNAPSHOTS" ] || fail "Expected E_HAS_SNAPSHOTS but got: $refusal_code"

blockers=$(echo "$refusal_output" | jq -r '.blockers // []' | jq length)
[ "$blockers" -gt 0 ] || fail "Expected blockers array but it is empty"
log "Refusal path E_HAS_SNAPSHOTS verified with $(jq length <<< "$(echo "$refusal_output" | jq '.blockers')") blockers"

log "=== Acceptance run complete ==="
log "All checks passed"
