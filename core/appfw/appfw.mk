# Cube SDK
# appfw packages

ROOTFS_PIP += ansible-core
ROOTFS_PIP += git+https://github.com/rancher/client-python.git@master

# ospurge, driven by hex_sdk's os_purge_project(), was the last openstack consumer
# left in the system python 3.9, and then the last one left in the antelope venv.
# It moves here with #625, which is what empties that venv and lets the release
# variables be promoted -- ospurge is not a service, so no component hop carried it.
#
# --no-deps with openstacksdk named alongside, rather than a plain install: ospurge
# requires the "typing" *backport*, which on python 3.11 is dead weight at best --
# pip drops a typing.py into site-packages that only the stdlib's precedence keeps
# from shadowing the real module. openstacksdk is the only requirement that matters
# and the constraint file pins it (3.0.0), so naming it directly gets the closure
# right without the backport.
#
# The rest of what ospurge imports it does not declare and does not get from --no-deps:
# pbr and six. Both are already in the caracal venv (six===1.16.0 is in caracal's own
# upper-constraints, and every service pulls pbr), which is the only reason this works
# -- a venv holding ospurge alone would fail at "import ospurge.main".
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
# resource does not survive openstacksdk 1.0 -- nor 3.0.0, which is what caracal
# pins: the same KeyError('container_name is not found...') reproduces unchanged
# there, so the patch carries forward rather than being dropped with the hop.
# Copied unconditionally rather than through the usual "[ -d ] && cp || /bin/true"
# guard: this patch is a correctness fix, not a decoration, and a silent skip here
# means os_purge_project() leaves every object behind while reporting success.
# See the file for the detail.
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
