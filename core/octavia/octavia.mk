# Cube SDK
# octavia installation

# The octavia services come from pip below, but the client has to stay an RPM
# under the *system* python: /usr/bin/openstack is `#!/usr/bin/python3` (3.9),
# and its `loadbalancer` subcommand is a stevedore entry point owned by
# python3-octaviaclient. The copy pip puts in the 3.10 venv is invisible to that
# CLI. core/sdk_sh/modules/sdk_os.sh drives octavia entirely through it --
# `loadbalancer list` (L404), the four flavorprofile/flavor pairs created at
# bootstrap (L1580-L1602) and `loadbalancer delete --cascade` (L1835) -- so
# without this RPM the load balancer bootstrap and teardown paths break.
# It used to arrive as an openstack-octavia-* dependency.
#
# NOTE: unlike heat, health_octavia_check() is *not* what depends on this.
# It checks systemd units, the monasca http_status metric and the octavia-hm0
# OVN port, never the OSC CLI -- so `cluster check` would have stayed green
# while the bootstrap paths above failed.
ROOTFS_DNF_NOARCH += python3-octaviaclient
#
# openstack-octavia-ui, the Horizon dashboard plugin, is replaced by the
# octavia-dashboard wheel installed further down. It was dropped when octavia moved
# to pip because Horizon still ran on the system python 3.9 and could not import a
# package from the 3.10 venv; #609 moved Horizon into the venv, so the Load Balancer
# panel comes back. Registering it is core/horizon's job, where every dashboard
# action lives.
#
# The octavia user and group are carried statically by
# core/heavyfs/account/centos9 (uid/gid 138), so the RDO spec's shadow-utils
# requirement has no equivalent here.

OCTAVIA_CONF_DIR := /etc/octavia
OCTAVIA_CONFDIR := $(ROOTDIR)$(OCTAVIA_CONF_DIR)

# https://releases.openstack.org/antelope/index.html -- last numeric 2023.1 revision,
# and the dashboard that pairs with the octavia 12.0.1 installed below. Horizon
# plugins are not in the antelope upper-constraints (that file only covers
# libraries), so the pin has to be explicit.
OCTAVIA_DASHBOARD_VER := 11.0.1

# install octavia
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# octavia-lib is NOT in octavia's requirements.txt, but the amphora
	$(Q)# provider driver imports it directly (octavia/api/drivers/
	$(Q)# amphora_driver/v2/driver.py imports octavia_lib.api.drivers), and that
	$(Q)# is the provider this deployment uses. The RPM pulled it in as
	$(Q)# python3-octavia-lib; pip will not, so it is listed explicitly.
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			octavia==12.0.1 \
			octavia-lib"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link the seven console scripts that run on the controller. The venv
	$(Q)# also gains amphora-agent, amphora-health-checker, amphora-interface,
	$(Q)# haproxy-vrrp-check and prometheus-proxy; those run *inside* the
	$(Q)# amphora VM and are provided by the amphora image, so they are left
	$(Q)# unlinked on purpose.
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/octavia-api /usr/bin/octavia-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/octavia-worker /usr/bin/octavia-worker
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/octavia-health-manager /usr/bin/octavia-health-manager
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/octavia-housekeeping /usr/bin/octavia-housekeeping
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/octavia-db-manage /usr/bin/octavia-db-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/octavia-driver-agent /usr/bin/octavia-driver-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/octavia-status /usr/bin/octavia-status

# install the octavia web ui plugin, the openstack-octavia-ui rpm's replacement.
# Registering its panel and settings snippet is core/horizon's job, where every
# dashboard action lives -- including the generated default_policies/octavia.yaml,
# because the snippet octavia-dashboard ships registers
# POLICY_FILES['load-balancer'] but no file to back it.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(NEXT_OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		octavia-dashboard==$(OCTAVIA_DASHBOARD_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/octavia
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/octavia

# stage the checked-in sample config, policy, dist conf and systemd units
# NOTE: core/octavia/oslo-config-generator/octavia.conf is not staged. It is the
# input that produced octavia.conf.sample and is kept in the repo for the next
# release hop; the image has no use for it.
rootfs_install::
	$(Q)cp -f $(COREDIR)/octavia/octavia.conf.sample $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/policy.yaml $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-dist.conf $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-api.service $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-worker.service $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-housekeeping.service $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-health-manager.service $(ROOTDIR)/tmp/octavia/

# install system directories and files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 750 /var/log/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/run/octavia
	$(Q)# per-service drop-in directories the systemd units pass with
	$(Q)# --config-dir; oslo.config fails to start if they do not exist.
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/common
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-api
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-worker
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-housekeeping
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-health-manager
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/octavia/octavia.conf.sample /etc/octavia/octavia.conf
	$(Q)# policy.yaml reverts the API to the legacy admin-or-owner RBAC, where a
	$(Q)# project member can manage the load balancers they own. Without it the
	$(Q)# Antelope default RBAC applies and every non-admin call needs an
	$(Q)# explicit load-balancer_* role.
	$(Q)#
	$(Q)# This is a verbatim copy of upstream etc/policy/admin_or_owner-policy.yaml
	$(Q)# (md5 c53952746cfb39f5c66f97bbe3bcb263), which is the same file the RPM
	$(Q)# delivered: openstack-octavia.spec:234 renames that exact path to
	$(Q)# /etc/octavia/policy.yaml and the spec carries no patches at all. The
	$(Q)# 0640 root:octavia set further down matches the %attr the spec put on
	$(Q)# it, so nothing about the effective RBAC moves with this hop.
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/octavia/policy.yaml /etc/octavia/policy.yaml
	$(Q)# 644, not 640: the units run as User=octavia and must be able to read
	$(Q)# this. It holds no secrets.
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-dist.conf /usr/share/octavia/octavia-dist.conf
	$(Q)# certificate tooling (unchanged from the RPM layout)
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/certs
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/certs/create_certificates.sh .$(OCTAVIA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/certs/octavia-certs.cnf .$(OCTAVIA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/dhclient.conf .$(OCTAVIA_CONF_DIR)
	$(Q)chroot $(ROOTDIR) chmod 755 /etc/octavia/create_certificates.sh
	$(Q)# install systemd unit files. All four are installed here now; under the
	$(Q)# RPM layout only worker and health-manager were, because
	$(Q)# openstack-octavia-{api,housekeeping} shipped the other two. The two
	$(Q)# units this branch rewrote are verbatim copies of the ones those RPMs
	$(Q)# installed, so dropping the RPMs does not change how they start. Note
	$(Q)# the checked-in files they replaced were never installed by anything --
	$(Q)# that is why they still pointed at /usr/local/bin.
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-api.service /usr/lib/systemd/system/octavia-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-worker.service /usr/lib/systemd/system/octavia-worker.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-housekeeping.service /usr/lib/systemd/system/octavia-housekeeping.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-health-manager.service /usr/lib/systemd/system/octavia-health-manager.service

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:octavia /etc/octavia/octavia.conf
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/octavia/octavia.conf
	$(Q)chroot $(ROOTDIR) chown root:octavia /etc/octavia/policy.yaml
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/octavia/policy.yaml
	$(Q)chroot $(ROOTDIR) chown octavia:octavia /var/lib/octavia
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/lib/octavia
	$(Q)chroot $(ROOTDIR) chown octavia:octavia /var/log/octavia
	$(Q)chroot $(ROOTDIR) chmod 0750 /var/log/octavia
	$(Q)chroot $(ROOTDIR) chown octavia:octavia /var/run/octavia
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/run/octavia

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/octavia

# hex_config reads this baseline and regenerates /etc/octavia/octavia.conf from
# it, so it has to be taken after the install step above has replaced the file
# the RPMs used to provide.
rootfs_install::
	$(Q)cp -f $(OCTAVIA_CONFDIR)/octavia.conf $(OCTAVIA_CONFDIR)/octavia.conf.def
