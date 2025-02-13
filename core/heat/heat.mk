# Cube SDK
# heat installation

ROOTFS_DNF_NOARCH += openstack-heat-api openstack-heat-api-cfn openstack-heat-engine openstack-heat-ui

HEAT_CONFDIR := $(ROOTDIR)/etc/heat

rootfs_install::
	$(Q)cp -f $(HEAT_CONFDIR)/heat.conf $(HEAT_CONFDIR)/heat.conf.def
