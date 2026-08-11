# Cube SDK
# appfw packages

ROOTFS_PIP += ansible-core
ROOTFS_PIP += git+https://github.com/rancher/client-python.git@master

# ospurge, driven by hex_sdk's os_purge_project(), was the last openstack consumer
# left in the system python 3.9: ROOTFS_PIP installs under the *yoga* constraint, so
# it is what held openstacksdk 0.62.0, keystoneauth1 4.5.0, osc-lib 2.5.0 and the
# oslo.* set there. Moving it into the antelope venv is what empties 3.9 out.
#
# --no-deps with openstacksdk named alongside, rather than a plain install: ospurge
# requires the "typing" *backport*, which on python 3.10 is dead weight at best --
# pip drops a typing.py into site-packages that only the stdlib's precedence keeps
# from shadowing the real module. openstacksdk is the only requirement that matters
# and the constraint file pins it (1.0.2), so naming it directly gets the closure
# right without the backport.
OSPURGE_REPO_URL := git+https://opendev.org/x/ospurge.git
OSPURGE_SRCDIR := $(ROOTDIR)$(OPENSTACK_HOME_DIR)/lib/python$(PYTHON_VER)/site-packages
OSPURGE_PATCHDIR := $(COREDIR)/appfw/$(OPENSTACK_RELEASE)_patch

rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install --no-deps \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		$(OSPURGE_REPO_URL) \
		openstacksdk
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# sdk_os.sh calls a bare "ospurge". The 3.9 install used to own
	$(Q)# /usr/local/bin/ospurge, which precedes /usr/bin in the PATH hex_sdk sets;
	$(Q)# with that gone, /usr/bin is where the console script belongs.
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ospurge /usr/bin/ospurge

# ospurge is unmaintained upstream (x/ospurge, last release 2018) and its swift
# resource does not survive openstacksdk 1.0. Copied unconditionally rather than
# through the usual "[ -d ] && cp || /bin/true" guard: this patch is a correctness
# fix, not a decoration, and a silent skip here means os_purge_project() leaves
# every object behind while reporting success. See the file for the detail.
rootfs_install::
	$(Q)cp -f $(OSPURGE_PATCHDIR)/ospurge/resources/swift.py $(OSPURGE_SRCDIR)/ospurge/resources/swift.py

rootfs_install::
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/resolv.conf
	$(Q)for i in {1..5}; do ! timeout 60 chroot $(ROOTDIR) ansible-galaxy collection install 'openstack.cloud:=1.8.0' --force || break ; done
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)mkdir -p $(ROOTDIR)/opt/appfw
	$(Q)cp -r $(COREDIR)/appfw/{ansible,bin} $(ROOTDIR)/opt/appfw/
	$(Q)cp -r $(TOP_BLDDIR)/core/appfw/appfw.tgz $(ROOTDIR)/opt/appfw/

#	$(Q)mkdir -p $(ROOTDIR)/opt/appfw/charts/{chartmuseum,docker-registry,keycloak}
#	$(Q)cp $(COREDIR)/appfw/charts/chartmuseum/*.yaml $(ROOTDIR)/opt/appfw/charts/chartmuseum/
#	$(Q)cp $(TOP_BLDDIR)/core/appfw/charts/chartmuseum/*.tgz $(ROOTDIR)/opt/appfw/charts/chartmuseum/
#	$(Q)cp $(COREDIR)/appfw/charts/docker-registry/*.yaml $(ROOTDIR)/opt/appfw/charts/docker-registry/
#	$(Q)cp $(TOP_BLDDIR)/core/appfw/charts/docker-registry/*.tgz $(ROOTDIR)/opt/appfw/charts/docker-registry/
#	$(Q)cp $(COREDIR)/appfw/charts/keycloak/keycloak-values.yaml $(ROOTDIR)/opt/appfw/charts/keycloak/
#	$(Q)cp $(TOP_BLDDIR)/core/appfw/charts/keycloak/*.tgz $(ROOTDIR)/opt/appfw/charts/keycloak/
