# Cube SDK
# appfw packages

ROOTFS_PIP += ansible-core
ROOTFS_PIP += git+https://github.com/rancher/client-python.git@master

# ospurge, driven by hex_sdk's os_purge_project(), was the last openstack consumer
# left in the system python 3.9, then the last one left in the antelope venv (#625),
# and then the last one left in the caracal venv. It moves here with #652, which is
# what empties that venv and lets the release variables be promoted -- ospurge is not
# a service, so no component hop carried it.
#
# ospurge goes in with --no-deps, rather than a plain install: it requires the
# "typing" *backport*, which on python 3.12 is dead weight at best -- pip drops a
# typing.py into site-packages that only the stdlib's precedence keeps from shadowing
# the real module. openstacksdk is the only requirement that matters and the
# constraint file pins it (4.4.1), so it is named in an install of its own, which
# brings its dependencies without the backport.
#
# The rest of what ospurge imports it does not declare: pbr and six, so those are named
# too. In the caracal venv all three used to arrive with something else -- the
# services, then horizon and the cli, and last skyline's apiserver -- which is why
# --no-deps on both ospurge and openstacksdk once worked. With skyline gone to the
# epoxy venv (#668), a fresh build's caracal venv held pip, setuptools, wheel, ospurge
# and openstacksdk and nothing else, and "import ospurge.main" failed on pbr. This
# venv already carries all three at the pinned versions (the openstack cli needs
# openstacksdk), so the install changes nothing here; it stays so that ospurge never
# again depends on who else happens to share its venv.
OSPURGE_REPO_URL := git+https://opendev.org/x/ospurge.git
OSPURGE_SRCDIR := $(ROOTDIR)$(OPENSTACK_HOME_DIR)/lib/python$(PYTHON_VER)/site-packages
OSPURGE_PATCHDIR := $(COREDIR)/appfw/$(OPENSTACK_RELEASE)_patch

rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install --no-deps \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		$(OSPURGE_REPO_URL)
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		openstacksdk pbr six
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# sdk_os.sh calls a bare "ospurge". The 3.9 install used to own
	$(Q)# /usr/local/bin/ospurge, which precedes /usr/bin in the PATH hex_sdk sets;
	$(Q)# with that gone, /usr/bin is where the console script belongs.
	$(Q)chroot $(ROOTDIR) ln -sf $(OPENSTACK_HOME_DIR)/bin/ospurge /usr/bin/ospurge

# ospurge is unmaintained upstream (x/ospurge, last release 2018) and its swift
# resource does not survive openstacksdk 1.0 -- nor 3.0.0 (caracal), nor 4.4.1, which
# is what epoxy pins: the same KeyError('container_name is not found...') reproduces
# unchanged under both, so the patch carries forward rather than being dropped with
# the hop.
# Copied unconditionally rather than through the usual "[ -d ] && cp || /bin/true"
# guard: this patch is a correctness fix, not a decoration, and a silent skip here
# means os_purge_project() leaves every object behind while reporting success.
# See the file for the detail.
#
# The two .patch files (each against the pristine .orig beside it) keep the purge
# inside the project it was asked to purge, which upstream does not:
#   - main.py hands connect_as_project() the project *name*, which with hex_sdk's OS_*
#     credentials leaves the purge connection scoped to the operator's own project.
#     What that connection lists by scope rather than by an explicit project filter is
#     then the operator's: `os_purge_project <p>` emptied the admin project's swift
#     account -- every container and object, volume-backups and log included -- instead
#     of <p>'s, and never saw <p>'s own volumes. Measured on openstacksdk 3.0.0 and
#     4.4.1 alike.
#   - resources/heat.py lists stacks with list_stacks(), and heat hands the admin role
#     ospurge grants itself every project's stacks, so even a correctly scoped purge
#     deleted the stacks of every project in the cloud.
# Applied the same unconditional way: patch exits non-zero on a missing file or a hunk
# that no longer applies.
rootfs_install::
	$(Q)cp -f $(OSPURGE_PATCHDIR)/ospurge/resources/swift.py $(OSPURGE_SRCDIR)/ospurge/resources/swift.py
	$(Q)patch --forward --no-backup-if-mismatch -r - $(OSPURGE_SRCDIR)/ospurge/main.py < $(OSPURGE_PATCHDIR)/ospurge/main.py.patch
	$(Q)patch --forward --no-backup-if-mismatch -r - $(OSPURGE_SRCDIR)/ospurge/resources/heat.py < $(OSPURGE_PATCHDIR)/ospurge/resources/heat.py.patch

heavy_components_install::
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
