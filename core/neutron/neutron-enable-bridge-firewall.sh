#!/bin/sh

# This script is triggered on every ovs/linuxbridge agent start. Its intent is
# to make sure the firewall for bridged traffic is enabled before we start an
# agent that may atttempt to set firewall rules on a bridge (a common thing for
# linuxbridge and ovs/hybrid backend setup).

# before enabling the firewall, load the relevant module
/usr/sbin/modprobe bridge

# on newer kernels (3.18+), sysctl knobs are split into a separate module;
# attempt to load it, but don't fail if it's missing (f.e. when running against
# an older kernel version)
/usr/sbin/modprobe br_netfilter 2>> /dev/null || :

# now enable the firewall in case it's disabled (f.e. rhel 7.2 and earlier)
for proto in ip ip6; do
    /usr/sbin/sysctl -w net.bridge.bridge-nf-call-${proto}tables=1
done
