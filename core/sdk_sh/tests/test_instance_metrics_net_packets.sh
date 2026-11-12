#!/bin/bash
#
# Unit test for vm.net.in_packets_sec in instance_metrics_collect (../modules/sdk_instance.sh).
#
# CubeCMP's auto-scaling group rule on inbound packets reads vm.net.in_packets_sec, monasca's
# name, from the telegraf database (#2328). It is a per-vNIC rate derived from the libvirt
# rx.pkts counter with the previous sample in the state file, like vm.net.in_bytes_sec.
#
# Self-contained: sources the module (functions only) with the state path redirected, and
# stubs libvirt, date and the shipper.
#   Run: bash test_instance_metrics_net_packets.sh   (exit 0 = pass)
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

U1=11111111-1111-1111-1111-111111111111   # two vNICs, previous sample 10 s ago
U2=22222222-2222-2222-2222-222222222222   # first sample, no previous one
U3=33333333-3333-3333-3333-333333333333   # counter below the previous sample: recreated
domain() {   # uuid name net-stats
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
nic() {   # index name rx.bytes rx.pkts
    printf '  net.%s.name=%s\n  net.%s.rx.bytes=%s\n  net.%s.rx.pkts=%s\n  net.%s.tx.bytes=0\n  net.%s.tx.pkts=0\n' \
           $1 $2 $1 $3 $1 $4 $1 $1
}
_instance_metrics_dump() {
    domain $U1 vm1 "  net.count=2
$(nic 0 tapaaaa 64000 1500)
$(nic 1 tapbbbb 9000 300)"
    domain $U2 vm2 "  net.count=1
$(nic 0 tapcccc 5000 70)"
    domain $U3 vm3 "  net.count=1
$(nic 0 tapdddd 100 5)"
}

printf '@ 990\nnrx:%s:tapaaaa 4000\nnrxp:%s:tapaaaa 1000\nnrxp:%s:tapbbbb 200\nnrxp:%s:tapdddd 900\n' \
       $U1 $U1 $U1 $U3 > $T/state
instance_metrics_collect $T
PROM=$T/cube_instance_metrics.prom
pkts() { grep "^vm.net.in_packets_sec,resource_id=$1,.*device=$2 " $T/lp ; }
value() { sed 's/.* value=\([^ ]*\) .*/\1/' ; }

# 1. one rate per vNIC, over the 10 s since the previous sample
chk "1 tapaaaa rate"   "$(pkts $U1 tapaaaa | value)" "50.000000"
chk "1 tapbbbb rate"   "$(pkts $U1 tapbbbb | value)" "10.000000"
# 2. tagged and timestamped like vm.net.in_bytes_sec, which CubeCMP filters on resource_id
chk "2 line"           "$(pkts $U1 tapaaaa)" \
    "vm.net.in_packets_sec,resource_id=$U1,tenant_id=p1,tenant_name=admin,vm_name=vm1,device=tapaaaa value=50.000000 1000"
chk "2 bytes unchanged" "$(grep "^vm.net.in_bytes_sec,resource_id=$U1,.*device=tapaaaa " $T/lp | value)" "6000.000000"
# 3. the counter is saved for the next run
chk "3 state tapaaaa"  "$(grep "^nrxp:$U1:tapaaaa " $T/state | awk '{print $2}')" "1500"
chk "3 state tapcccc"  "$(grep "^nrxp:$U2:tapcccc " $T/state | awk '{print $2}')" "70"
# 4. no previous sample: no rate yet
chk "4 first sample"   "$(grep -c "^vm.net.in_packets_sec,resource_id=$U2," $T/lp)" "0"
# 5. a counter below its previous value: the domain was recreated, no rate
chk "5 recreated"      "$(grep -c "^vm.net.in_packets_sec,resource_id=$U3," $T/lp)" "0"
chk "5 state reset"    "$(grep "^nrxp:$U3:tapdddd " $T/state | awk '{print $2}')" "5"
# 6. the Prometheus counter is still the raw libvirt value
chk "6 prometheus"     "$(grep "^ceilometer_network_incoming_packets{resource=\"$U1\".*device=\"tapaaaa\"" $PROM | awk '{print $2}')" "1500"

rm -rf "$T"
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
