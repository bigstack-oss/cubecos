#!/bin/bash
#
# Unit test for the vCPU CPU figures in instance_metrics_collect (../modules/sdk_instance.sh).
#
# Under fio on a ceph disk a guest at 3.8% CPU showed 26-32% on the Instance dashboard
# (#897): ceilometer_cpu is the whole qemu process, librbd I/O threads included. The
# human-facing figures now come from cube_instance_vcpu_time, the vCPU threads only, while
# ceilometer_cpu stays the whole process for Watcher.
#
# Self-contained: sources the module (functions only) with the state path redirected, and
# stubs libvirt, date and the shipper.
#   Run: bash test_instance_metrics_vcpu_time.sh   (exit 0 = pass)
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_instance.sh"
T=$(mktemp -d)

sed "s#/run/cube_instance_metrics.state#$T/state#" "$SRC" > $T/sdk_instance.sh
PROG=test source $T/sdk_instance.sh
type instance_metrics_collect >/dev/null 2>&1 || { echo "FAIL: instance_metrics_collect not loaded"; exit 1; }

pass=0 fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# ---- fixture ---------------------------------------------------------------
virsh() { :; }
date() { echo 1000 ; }
MakeTemp() { mktemp -p "$T" ; }
RemoveTempFiles() { :; }
_instance_metrics_ship() { cp "$1" "$T/lp" ; }
_instance_l3_collect() { :; }

U1=11111111-1111-1111-1111-111111111111
U2=22222222-2222-2222-2222-222222222222
VCPU_STATS="  vcpu.current=2
  vcpu.maximum=2
  vcpu.0.state=1
  vcpu.0.time=12000000000000
  vcpu.1.state=1
  vcpu.1.time=3000000000001"
domain() {   # uuid name vcpu-stats
    cat <<EOF
<domain type='kvm'>
  <name>instance-$2</name>
  <uuid>$1</uuid>
  <metadata>
    <nova:instance xmlns:nova="http://openstack.org/xmlns/libvirt/nova/1.1">
      <nova:name>$2</nova:name>
      <nova:flavor name="t2.medium">
        <nova:vcpus>2</nova:vcpus>
      </nova:flavor>
      <nova:owner>
        <nova:project uuid="p1">admin</nova:project>
      </nova:owner>
    </nova:instance>
  </metadata>
</domain>
@@STATS@@
Domain: 'instance-$2'
  cpu.time=90000000000000
$3
@@END@@
EOF
}
_instance_metrics_dump() { domain $U1 vm1 "$VCPU_STATS" ; domain $U2 vm2 "" ; }

# previous run 10 s earlier: vm1 vCPUs 2 s behind -> 0.2 cores of 2 = 10%
printf '@ 990\nvcpu:%s 14998000000001\n' $U1 > $T/state
instance_metrics_collect $T
PROM=$T/cube_instance_metrics.prom
val() { grep "^$1{resource=\"$2\"" $PROM | awk '{print $2}' ; }

# 1. vCPU time is the sum of the vCPU threads, printed as a whole integer
chk "1 vcpu_time sum"   "$(val cube_instance_vcpu_time $U1)" "15000000000001"
# 2. ceilometer_cpu is still the whole process (Watcher)
chk "2 ceilometer_cpu"  "$(val ceilometer_cpu $U1)" "90000000000000"
# 3. the influx CPU percentage follows the vCPU time, not cpu.time
chk "3 cpu pct"         "$(grep "^vm.cpu.utilization_norm_perc,resource_id=$U1" $T/lp | sed 's/.* value=\([^ ]*\) .*/\1/')" "10.000000"
chk "3 state saved"     "$(grep "^vcpu:$U1 " $T/state | awk '{print $2}')" "15000000000001"
# 4. no vCPU stats: no vCPU series and no percentage, rather than a whole-process stand-in
chk "4 no vcpu_time"    "$(val cube_instance_vcpu_time $U2)" ""
chk "4 no cpu pct"      "$(grep -c "^vm.cpu.utilization_norm_perc,resource_id=$U2" $T/lp)" "0"
chk "4 ceilometer_cpu"  "$(val ceilometer_cpu $U2)" "90000000000000"
# 5. declared once as a counter
chk "5 TYPE"            "$(grep -c '^# TYPE cube_instance_vcpu_time counter$' $PROM)" "1"

rm -rf "$T"
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
