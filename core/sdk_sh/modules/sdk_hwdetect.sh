# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

hwdetect_cluster_ready()
{
    if ! is_control_node ; then
        return 0
    fi

    local image_id=$($OPENSTACK image list | awk '/ Cirros /{print $2}')
    local flavor_id=$($OPENSTACK flavor list | awk '/ t2.medium /{print $2}')
    local iprange=$@

    if [ -z "$image_id" -o -z "$flavor_id" ] ; then
        $HEX_SDK os_image_import /etc/glance cirros-0.4.0-x86_64-disk.qcow2 Cirros && rm -f /etc/glance/cirros-0.4.0-x86_64-disk.qcow2
        $HEX_SDK os_image_import /etc/glance alpine-tools.qcow2 Alpine && rm -f /etc/glance/alpine-tools.qcow2

        # ref: https://aws.amazon.com/ec2/instance-types/
        Quiet -n $OPENSTACK flavor create --vcpus 1 --ram 128 --disk 1 --public t2.pico
        Quiet -n $OPENSTACK flavor create --vcpus 1 --ram 512 --disk 10 --public t2.nano
        Quiet -n $OPENSTACK flavor create --vcpus 1 --ram 1024 --disk 20 --public t2.micro
        Quiet -n $OPENSTACK flavor create --vcpus 1 --ram 2048 --disk 40 --public t2.small
        Quiet -n $OPENSTACK flavor create --vcpus 2 --ram 4096 --disk 80 --public t2.medium
        Quiet -n $OPENSTACK flavor create --vcpus 2 --ram 8192 --disk 160 --public t2.large
        Quiet -n $OPENSTACK flavor create --vcpus 4 --ram 16384 --disk 160 --property hw:cpu_sockets=1 --property hw:cpu_cores=2 --property hw:cpu_threads=2 --public t2.xlarge
        Quiet -n $OPENSTACK flavor create --vcpus 8 --ram 32768 --disk 160 --property hw:cpu_sockets=2 --property hw:cpu_cores=2 --property hw:cpu_threads=2 --public t2.2xlarge

        Quiet -n $OPENSTACK flavor create --vcpus 2 --ram 4096 --disk 40 --public vgpu.example
        Quiet -n $OPENSTACK flavor set vgpu.example --property "resources:VGPU=1"

        Quiet -n $OPENSTACK flavor create --vcpus 2 --ram 4096 --disk 40 --public pgpu.example
        Quiet -n $OPENSTACK flavor set pgpu.example --property 'accel:device_profile=<profile_name>'
    fi

    if [ -n "$iprange" ] ; then
        Quiet -n $OPENSTACK network create --share --external --provider-physical-network provider --provider-network-type flat public
        Quiet -n $OPENSTACK subnet create $iprange --dhcp --network public public__subnet
    fi
}
