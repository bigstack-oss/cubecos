#!/bin/bash
# Render $OUT/tempest.conf for the cluster at $VIP; create the Cirros image, flavors and heat-net if missing.
# Fixtures created here are listed in $OUT/created.txt for teardown.
set -euo pipefail
: "${VIP:?}" "${ADMIN_USER:?}" "${ADMIN_PASSWORD:?}" "${ADMIN_PROJECT:?}" "${OUT:?}" "${WORKSPACE:?}"
IMAGE_NAME=tempest-cirros-0.6.2
created() { echo "$1 $2" >> "$OUT/created.txt"; }

image_id=$(openstack image list --name $IMAGE_NAME -f value -c ID | head -1)
if [ -z "$image_id" ]; then
    # scsi cdrom: older cirros kernels can't see q35's sata cdrom (config drive)
    image_id=$(openstack image create $IMAGE_NAME --public --disk-format qcow2 --container-format bare \
               --property hw_cdrom_bus=scsi --file /opt/tempest/cirros.img -f value -c id)
    created image "$image_id"
fi
flavor() {  # name ram_mb disk_gb
    local id
    id=$(openstack flavor show "$1" -f value -c id 2>/dev/null) && { echo "$id"; return; }
    id=$(openstack flavor create "$1" --ram "$2" --disk "$3" --vcpus 1 -f value -c id)
    created flavor "$id"; echo "$id"
}
flavor_id=$(flavor tempest-nano 512 2)
flavor_alt_id=$(flavor tempest-micro 1024 4)
read -r pub_id pub_name < <(openstack network list --external -f value -c ID -c Name | head -1) || true
[ -n "${pub_id:-}" ] || { echo "no external network on $VIP"; exit 2; }

# heat_plugin's fixed_network_name defaults to heat-net
if ! openstack network show heat-net >/dev/null 2>&1; then
    openstack network create heat-net >/dev/null
    openstack subnet create heat-subnet --network heat-net --subnet-range 10.97.0.0/24 >/dev/null
    openstack router create heat-router --external-gateway "$pub_id" >/dev/null
    openstack router add subnet heat-router heat-subnet
    created router heat-router; created network heat-net
fi
net_ext=$(openstack extension list --network -f value -c Alias | sort | paste -sd,)
vol_ext=$(openstack extension list --volume -f value -c Alias | sort | paste -sd,)

umask 077
python3 - /opt/tempest/tempest.conf.in "$OUT/tempest.conf" <<EOF
import os, sys
s = open(sys.argv[1]).read()
for k, v in {"WORKSPACE": "$WORKSPACE", "VIP": "$VIP", "ADMIN_USER": "$ADMIN_USER", "ADMIN_PROJECT": "$ADMIN_PROJECT",
             "IMAGE_ID": "$image_id", "IMAGE_NAME": "$IMAGE_NAME", "FLAVOR_ID": "$flavor_id",
             "FLAVOR_ALT_ID": "$flavor_alt_id", "FLAVOR_NAME": "tempest-nano", "PUBLIC_NET_ID": "$pub_id",
             "PUBLIC_NET_NAME": "$pub_name", "NET_EXTENSIONS": "$net_ext", "VOL_EXTENSIONS": "$vol_ext"}.items():
    s = s.replace("@%s@" % k, v)
open(sys.argv[2], "w").write(s.replace("@ADMIN_PASSWORD@", os.environ["ADMIN_PASSWORD"]))
EOF
ln -sf "$OUT/tempest.conf" "$WORKSPACE/etc/tempest.conf"
echo "rendered tempest.conf (image $image_id, flavors $flavor_id/$flavor_alt_id, public $pub_name)"
