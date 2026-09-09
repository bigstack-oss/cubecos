#!/bin/bash
#
# Unit test for storage_usage_guest_disks (../modules/sdk_storage.sh).
#
# guest-get-fsinfo returns one entry per *mountpoint*, so a filesystem mounted
# twice (bind mount, btrfs subvolume, /var/lib/docker on the root device) is
# reported twice with identical counts and must be deduped by device before
# summing, or the VM's usage doubles. tmpfs and friends are RAM, not disk.
#
# Four states because each needs a different fix: no_channel (image lacks
# hw_qemu_guest_agent), no_agent (not installed/running -- also the transient
# state for ~25s after boot while udev starts qemu-ga), agent_too_old (pre-5.2,
# answers but omits byte fields), exact. An old agent's answer is "unknown",
# never 0: a 0 renders as an empty disk.
#
# Per-filesystem rows drive the alarm; the summed row drives the GUI. The 109MB
# ESP in the real sky payload must floor out (a small always-full /boot/efi is
# normal) while the 858MB /boot must not -- it is the one worth alarming on.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$DIR/../modules/sdk_storage.sh"

b="$(awk '/^storage_usage_guest_disks\(\)/{p=1} p{print} p&&/^}/{exit}' "$M")"
[ -n "$b" ] || { echo "FAIL: storage_usage_guest_disks not extracted"; exit 1; }
eval "$b"
STORAGE_USAGE_FS_FLOOR=268435456

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# cmd -pv emits the "<host>|<ret>|<output>" shape sdk_cmd.sh produces.
# vm-1: real appfw shape (/, /boot, /boot/efi) + a bind-mounted duplicate + tmpfs
# vm-2: connected but pre-5.2 agent (no byte fields)
# vm-3: channel present, disconnected
# vm-4: no channel at all
cmd(){
    cat <<'OUT'
cmp1|0|GUESTFS vm-1 ok {"return":[{"name":"vda1","mountpoint":"/","type":"ext4","total-bytes":10000000000,"used-bytes":4000000000},{"name":"vda1","mountpoint":"/var/lib/docker","type":"ext4","total-bytes":10000000000,"used-bytes":4000000000},{"name":"vdb1","mountpoint":"/data","type":"xfs","total-bytes":50000000000,"used-bytes":1000000000},{"name":"tmpfs","mountpoint":"/run","type":"tmpfs","total-bytes":800000000,"used-bytes":1000000}]}
cmp1|0|GUESTFS vm-2 ok {"return":[{"name":"vda1","mountpoint":"/","type":"ext4"}]}
cmp2|0|GUESTFS vm-3 no_agent {}
cmp2|0|GUESTFS vm-4 no_channel {}
OUT
}

out="$(storage_usage_guest_disks)"
g(){ echo "$out" | jq -r --arg v "$1" 'select(.scope=="vm" and .instance_id==$v) | '"$2"; }
f(){ echo "$out" | jq -r --arg v "$1" --arg m "$2" 'select(.scope=="fs" and .instance_id==$v and .mountpoint==$m) | '"$3"; }

chk "vm row count"        "$(echo "$out" | jq -r 'select(.scope=="vm")' | grep -c instance_id)" "4"
chk "deduped total"       "$(g vm-1 .guest_total_bytes)"   "60000000000"
chk "deduped used"        "$(g vm-1 .guest_used_bytes)"    "5000000000"
chk "tmpfs excluded"      "$(g vm-1 .fs_count)"            "2"
chk "confidence exact"    "$(g vm-1 .confidence)"          "exact"
chk "old agent total"     "$(g vm-2 .guest_total_bytes)"   "null"
chk "old agent state"     "$(g vm-2 .confidence)"          "agent_too_old"
chk "disconnected state"  "$(g vm-3 .confidence)"          "no_agent"
chk "no channel state"    "$(g vm-4 .confidence)"          "no_channel"
chk "no channel bytes"    "$(g vm-4 .guest_used_bytes)"    "null"

chk "fs rows for vm-1"    "$(echo "$out" | jq -r 'select(.scope=="fs")' | grep -c instance_id)" "2"
chk "/ percent"           "$(f vm-1 / .used_percent)"      "40"
chk "/data percent"       "$(f vm-1 /data .used_percent)"  "2"
chk "fs device carried"   "$(f vm-1 / .device)"            "vda1"
chk "dup mountpoint gone" "$(f vm-1 /var/lib/docker .mountpoint)" ""
chk "agentless has no fs" "$(echo "$out" | jq -r 'select(.scope=="fs" and .instance_id!="vm-1")' | grep -c .)" "0"

# floor: a 109MB ESP floors out, an 858MB /boot does not
cmd(){ echo 'cmp1|0|GUESTFS vm-9 ok {"return":[{"name":"sda15","mountpoint":"/boot/efi","type":"vfat","total-bytes":109395456,"used-bytes":103395456},{"name":"sda16","mountpoint":"/boot","type":"ext4","total-bytes":858513408,"used-bytes":815587737}]}'; }
o2="$(storage_usage_guest_disks)"
chk "ESP floored out"     "$(echo "$o2" | jq -r 'select(.scope=="fs" and .mountpoint=="/boot/efi")' | grep -c .)" "0"
chk "/boot kept"          "$(echo "$o2" | jq -r 'select(.scope=="fs" and .mountpoint=="/boot") | .used_percent')" "94"
chk "sum still counts ESP" "$(echo "$o2" | jq -r 'select(.scope=="vm") | .guest_total_bytes')" "967908864"

cmd(){ :; }
chk "no hosts is empty"   "$(storage_usage_guest_disks | grep -c .)" "0"

echo "pass=$pass fail=$fail"; [ $fail -eq 0 ]
