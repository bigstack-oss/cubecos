# Cube SDK
# designate installation

ROOTFS_DNF += bind bind-utils

# python3-designateclient stays a yoga rpm under the *system* python 3.9. It owns the
# "dns" osc plugin entry point that /usr/bin/openstack -- still `#!/usr/bin/python3` --
# resolves, and hex_sdk's health_designate_check() drives
# `openstack dns service list` through it, counting the api/central/worker/producer/mdns
# rows that report UP.
#
# It has to be named here because it used to arrive in 3.9 only as a side effect of the
# yoga horizon closure that #609 removed. Nothing in this tree ever asked for it, so it
# disappeared silently and `cluster check` reported "DNSaaS NG [ designate(9 api not all
# up) ]" while every designate unit was active -- the check could not run its query at
# all. Every other service hex_sdk drives this way already names its client explicitly:
# heat and manila and octavia as rpms, watcher as an explicit pip install.
ROOTFS_DNF_NOARCH += python3-designateclient

NAMED_CONF_FILES := /etc/named*
NAMED_APP_DIR := /var/named

# https://releases.openstack.org/teams/designate.html
DESIGNATE_REPO_URL := https://github.com/openstack/designate.git
DESIGNATE_DASHBOARD_REPO_URL := https://github.com/openstack/designate-dashboard.git

DESIGNATE_CONF_DIR := /etc/designate
DESIGNATE_APP_DIR := /var/lib/designate
DESIGNAT_LOG_DIR := /var/log/designate

DESIGNATE_BINDIR := $(ROOTDIR)/opt/openstack-antelope/bin
DESIGNATE_BIN_PATCHDIR := $(COREDIR)/designate/$(NEXT_OPENSTACK_RELEASE)_bin_patch

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/designate
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/designate

# install designate inside the python 3.10 virtual environment
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(NEXT_OPS_GITHUB_BRANCH_02) --depth 1 $(DESIGNATE_REPO_URL) /tmp/designate/designate
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		-r /tmp/designate/designate/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/designate/designate && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)chroot $(ROOTDIR) timeout 120 git clone -b $(NEXT_OPS_GITHUB_BRANCH_02) --depth 1 $(DESIGNATE_DASHBOARD_REPO_URL) /tmp/designate/designate-dashboard
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		-r /tmp/designate/designate-dashboard/requirements.txt
	$(Q)chroot $(ROOTDIR) bash -c "cd /tmp/designate/designate-dashboard && \
		/opt/openstack-antelope/bin/python setup.py install"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/designate-agent /usr/bin/designate-agent
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/designate-api /usr/bin/designate-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/designate-api-wsgi /usr/bin/designate-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/designate-central /usr/bin/designate-central
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/designate-manage /usr/bin/designate-manage
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/designate-mdns /usr/bin/designate-mdns
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/designate-producer /usr/bin/designate-producer
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/designate-rootwrap /usr/bin/designate-rootwrap
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/designate-sink /usr/bin/designate-sink
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/designate-status /usr/bin/designate-status
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/designate-worker /usr/bin/designate-worker

# install custom files
# for designate
rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/named/named.conf.in ./etc/
	$(Q)chroot $(ROOTDIR) sh -c "chown named:named $(NAMED_CONF_FILES) $(NAMED_APP_DIR)"

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(DESIGNATE_CONF_DIR) $(DESIGNATE_APP_DIR) $(DESIGNAT_LOG_DIR)
	$(Q)chroot $(ROOTDIR) chown designate:designate $(DESIGNATE_CONF_DIR) $(DESIGNATE_APP_DIR) $(DESIGNAT_LOG_DIR)
	$(Q)cp -f $(ROOTDIR)/tmp/designate/designate/etc/designate/policy.yaml.sample $(ROOTDIR)$(DESIGNATE_CONF_DIR)/policy.yaml
	$(Q)cp -f $(ROOTDIR)/tmp/designate/designate/etc/designate/api-paste.ini $(ROOTDIR)$(DESIGNATE_CONF_DIR)/api-paste.ini
	$(Q)cp -f $(ROOTDIR)/tmp/designate/designate/etc/designate/rootwrap.conf.sample $(ROOTDIR)$(DESIGNATE_CONF_DIR)/rootwrap.conf
	$(Q)cp -rf $(ROOTDIR)/tmp/designate/designate/etc/designate/rootwrap.d $(ROOTDIR)$(DESIGNATE_CONF_DIR)/
	$(Q)# -f: treat the destination as the full target path. Without it the install
	$(Q)# script takes designate.conf.def for a directory and drops the sample
	$(Q)# inside it, so config_designate.cpp's LoadConfig() finds nothing to read.
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/designate/designate.conf.sample .$(DESIGNATE_CONF_DIR)/designate.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate_sudoers ./etc/sudoers.d/
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-agent.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-central.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-worker.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-producer.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/designate/designate-mdns.service ./lib/systemd/system

rootfs_install::
	$(Q)[ -d $(DESIGNATE_BIN_PATCHDIR) ] && cp -rf $(DESIGNATE_BIN_PATCHDIR)/* $(DESIGNATE_BINDIR)/ || /bin/true

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/designate
