#!/bin/bash
#
# Unit test for the per-instance L3 cache occupancy in instance_metrics_collect
# (../modules/sdk_instance.sh): resctrl mon group per running qemu, pruning, the summed
# llc_occupancy as ceilometer_cpu_l3_cache, and silence on a CPU without CMT.
#
# Self-contained: fake /proc, /sys/fs/resctrl and /run/libvirt/qemu trees; libvirt, the
# mount and the shipper are stubbed.
#   Run: bash test_instance_l3_cache.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_instance.sh"
T=$(mktemp -d)

sed "s#/run/cube_instance_metrics.state#$T/state#" "$SRC" > $T/sdk_instance.sh
PROG=test source $T/sdk_instance.sh
type _instance_l3_collect >/dev/null 2>&1 || { echo "FAIL: _instance_l3_collect not loaded"; rm -rf "$T"; exit 1; }

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ---------------------------------------------------------------
_INSTANCE_L3_ROOT=$T/resctrl
_INSTANCE_L3_CPUINFO=$T/cpuinfo
_INSTANCE_L3_PROC=$T/proc
_INSTANCE_L3_RUN=$T/run
mounts() { cat $T/mounts 2>/dev/null || echo 0; }
_instance_l3_mount() { echo $(( $(mounts) + 1 )) > $T/mounts; mkdir -p $T/resctrl/info/L3_MON $T/resctrl/mon_groups
                       printf 'llc_occupancy\nmbm_total_bytes\n' > $T/resctrl/info/L3_MON/mon_features; }
virsh() { :; }
date() { echo 1000 ; }
MakeTemp() { mktemp -p "$T" ; }
RemoveTempFiles() { :; }
_instance_metrics_ship() { :; }

U1=11111111-1111-1111-1111-111111111111
U2=22222222-2222-2222-2222-222222222222
U3=33333333-3333-3333-3333-333333333333   # cachetune domain, owned by libvirt
STALE=44444444-4444-4444-4444-444444444444
mkdir -p $T/proc $T/run
echo "flags : fpu cat_l3 cqm_llc cqm_occup_llc cqm_mbm_total" > $T/cpuinfo
qemu() {   # pid uuid res tids...
    local pid=$1 uuid=$2 res=$3 t ; shift 3
    mkdir -p $T/proc/$pid/task
    printf '/usr/libexec/qemu-kvm\0-name\0guest=x\0-uuid\0%s\0-smp\0001\0' $uuid > $T/proc/$pid/cmdline
    printf 'res:%s\nmon:\n' "$res" > $T/proc/$pid/cpu_resctrl_groups
    for t in "$@" ; do mkdir -p $T/proc/$pid/task/$t ; done
    printf '%s' $pid > $T/run/instance-$pid.pid    # libvirt writes no newline
}
qemu 100 $U1 "" 100 101 102
qemu 200 $U2 "/" 200
qemu 300 $U3 "/libvirt-vm3" 300
domain() {
    printf '<domain type="kvm">\n  <name>instance-%s</name>\n  <uuid>%s</uuid>\n</domain>\n@@STATS@@\n  cpu.time=5\n@@END@@\n' $2 $1
}
_instance_metrics_dump() { domain $U1 1 ; domain $U2 2 ; }

# ---- 1. first run: mounts, creates groups, no occupancy readable yet --------
out=$(_instance_l3_collect)
chk "1 mounted once"        "$(mounts)" "1"
chk "1 group U1"            "$([ -d $T/resctrl/mon_groups/$U1 ] && echo y)" "y"
chk "1 group U2"            "$([ -d $T/resctrl/mon_groups/$U2 ] && echo y)" "y"
chk "1 no group cachetune"  "$([ -d $T/resctrl/mon_groups/$U3 ] && echo y)" ""
chk "1 tasks written"       "$(cat $T/resctrl/mon_groups/$U1/tasks)" "102"   # fake file keeps last write
chk "1 nothing to report"   "$out" ""

# ---- 2. occupancy summed over L3 domains; Unavailable skipped; stale pruned --
mkdir -p $T/resctrl/mon_groups/$U1/mon_data/mon_L3_00 $T/resctrl/mon_groups/$U1/mon_data/mon_L3_01
echo 1048576 > $T/resctrl/mon_groups/$U1/mon_data/mon_L3_00/llc_occupancy
echo 524288  > $T/resctrl/mon_groups/$U1/mon_data/mon_L3_01/llc_occupancy
mkdir -p $T/resctrl/mon_groups/$U2/mon_data/mon_L3_00
echo Unavailable > $T/resctrl/mon_groups/$U2/mon_data/mon_L3_00/llc_occupancy
mkdir -p $T/resctrl/mon_groups/$STALE $T/resctrl/mon_groups/other-tool
out=$(_instance_l3_collect)
chk "2 sum U1"              "$out" "$U1 1572864"
chk "2 mount reused"        "$(mounts)" "1"
chk "2 stale pruned"        "$([ -d $T/resctrl/mon_groups/$STALE ] && echo y)" ""
chk "2 foreign group kept"  "$([ -d $T/resctrl/mon_groups/other-tool ] && echo y)" "y"

# ---- 3. emitted in the textfile with the usual labels -----------------------
instance_metrics_collect $T
PROM=$T/cube_instance_metrics.prom
chk "3 series"              "$(grep "^ceilometer_cpu_l3_cache{resource=\"$U1\"" $PROM | awk '{print $2}')" "1572864"
chk "3 none for U2"         "$(grep -c "^ceilometer_cpu_l3_cache{resource=\"$U2\"" $PROM)" "0"
chk "3 TYPE gauge"          "$(grep -c '^# TYPE ceilometer_cpu_l3_cache gauge$' $PROM)" "1"
chk "3 cpu still there"     "$(grep -c "^ceilometer_cpu{resource=\"$U1\"" $PROM)" "1"

# ---- 4. VM stopped: its pid file goes, its group is removed -------------------
rm -f $T/run/instance-200.pid
rm -rf $T/resctrl/mon_groups/$U2/*          # a real resctrl rmdir ignores contents
_instance_l3_collect >/dev/null
chk "4 stopped pruned"      "$([ -d $T/resctrl/mon_groups/$U2 ] && echo y)" ""
chk "4 running kept"        "$([ -d $T/resctrl/mon_groups/$U1 ] && echo y)" "y"

# ---- 5. no CMT: no mount, no groups, no output, rc 0 -------------------------
rm -rf $T/resctrl $T/mounts
echo "flags : fpu sse2" > $T/cpuinfo
out=$(_instance_l3_collect) ; rc=$?
chk "5 rc"                  "$rc" "0"
chk "5 no mount"            "$(mounts)" "0"
chk "5 no output"           "$out" ""
chk "5 no tree"             "$([ -d $T/resctrl ] && echo y)" ""

# ---- 6. CMT flag but resctrl cannot mount: silent ----------------------------
echo "flags : cqm_occup_llc" > $T/cpuinfo
_instance_l3_mount() { return 1; }
out=$(_instance_l3_collect) ; rc=$?
chk "6 rc"                  "$rc" "0"
chk "6 no output"           "$out" ""

rm -rf "$T"
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
