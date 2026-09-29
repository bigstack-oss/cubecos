# Cube SDK
# openstack skyline installation

SKYLINE_CONF_DIR := /etc/skyline
SKYLINE_POLICY_DIR := $(SKYLINE_CONF_DIR)/policy
SKYLINE_APP_DIR := /var/lib/skyline
SKYLINE_LOG_DIR := /var/log/skyline

# skyline runs out of the epoxy venv, beside every service it fronts, rather than the
# caracal one #641 gave it. gunicorn and alembic come from skyline-apiserver's own
# requirements inside that venv, which is why ROOTFS_PIP_NC carries no gunicorn --
# nothing else used the system copy.
SKYLINE_VENV := $(OPENSTACK_HOME_DIR)
SKYLINE_PIP := $(SKYLINE_VENV)/bin/pip
SKYLINE_PIP_C := -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT)

# https://releases.openstack.org/epoxy/index.html#epoxy-skyline-apiserver -- 6.0.1 is
# the newest 2025.1 release.
#
# This is upstream's release, not the bigstack-oss fork any more. The fork carried six
# commits on 4.0.1; at 6.0.1 upstream has the gunicorn unix-socket fix and a newer
# databases floor, and of the other two only one is still wanted:
#   - f6e1237 put the pre-secure-RBAC rules back into skyline's copy of the barbican,
#     heat, ironic, ironic-inspector and neutron policies, for yoga services that
#     honoured them. The epoxy heat, ironic and neutron do not, so it made skyline
#     offer actions they refuse; the console reads no ironic or ironic-inspector rule
#     at all, and in barbican it only changed the creator role, which no user holds.
#     It also left neutron:remove_extraroutes unparseable, denied to everyone and
#     logging a traceback per worker on every start (#1540).
#   - e1d0945 lifted python-jose past 3.3.0 (CVE-2024-33663, CVE-2024-33664). Upstream
#     still caps it at <=3.3.0 on every branch, and a constraint can only narrow a
#     requirement, never lift its ceiling, so that one line is carried as a patch.
SKYLINE_APISERVER_VER := 6.0.1

# Reviewable unified diffs against the sdist, <rel>.patch beside a pristine <rel>.orig.
# They are applied to a freshly unpacked tree on every build, so --forward never sees
# an already-patched file.
SKYLINE_PATCHDIR := $(COREDIR)/skyline/$(OPENSTACK_RELEASE)_patch

# skyline user/group/directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(SKYLINE_CONF_DIR) $(SKYLINE_POLICY_DIR) $(SKYLINE_APP_DIR) $(SKYLINE_LOG_DIR)

# for RC builds
heavyfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(SKYLINE_CONF_DIR) $(SKYLINE_POLICY_DIR) $(SKYLINE_APP_DIR) $(SKYLINE_LOG_DIR)

# note: `pip install .` replaces `python3 setup.py install` -- setuptools dropped the
# install command, and the venv is on a setuptools new enough to have removed it.
# skyline-apiserver installation
#
# From the sdist, not the wheel: pbr writes the installed metadata from requirements.txt
# at build time, so the patched python-jose floor is what pip resolves against, pip check
# stays clean, and the sbom sees the python-jose that is actually installed.
rootfs_install::
	$(Q)# only the epoxy venv is cleared: an RC build starts from its release's published
	$(Q)# full build, whose skyline lives there too. Neither that nor a fresh build has a
	$(Q)# copy in the system python 3.9 (skyline left it in #641) or in the caracal venv
	$(Q)# (#641 to #668, and the venv itself is gone since #652), so there is nothing else
	$(Q)# to clear
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) uninstall -y skyline-apiserver
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) cache remove skyline-apiserver
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) download --no-deps --no-binary :all: \
		-d /skyline-apiserver-sdist skyline-apiserver==$(SKYLINE_APISERVER_VER)
	$(Q)mkdir -p $(ROOTDIR)/skyline-apiserver
	$(Q)tar -xzf $(ROOTDIR)/skyline-apiserver-sdist/skyline_apiserver-$(SKYLINE_APISERVER_VER).tar.gz \
		--strip-components=1 -C $(ROOTDIR)/skyline-apiserver
	$(Q)set -e; for p in $$(find $(SKYLINE_PATCHDIR) -name '*.patch' 2>/dev/null | sort); do \
		rel=$${p#$(SKYLINE_PATCHDIR)/}; tgt=$(ROOTDIR)/skyline-apiserver/$${rel%.patch}; \
		echo "  PATCH $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "skyline: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done
	$(Q)chroot $(ROOTDIR) sh -c "cd /skyline-apiserver && $(SKYLINE_PIP) install $(SKYLINE_PIP_C) -r requirements.txt && $(SKYLINE_PIP) install $(SKYLINE_PIP_C) ."
	$(Q)cp ${ROOTDIR}/skyline-apiserver/etc/gunicorn.py ${ROOTDIR}/etc/skyline/gunicorn.py
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/skyline/skyline-apiserver.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/skyline/skyline.yaml.in .$(SKYLINE_CONF_DIR)/skyline.yaml.in
	$(Q)rm -rf $(ROOTDIR)/skyline-apiserver $(ROOTDIR)/skyline-apiserver-sdist

# for RC builds -- the same pinned release, so the same recipe
heavyfs_install::
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) uninstall -y skyline-apiserver
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) cache remove skyline-apiserver
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) download --no-deps --no-binary :all: \
		-d /skyline-apiserver-sdist skyline-apiserver==$(SKYLINE_APISERVER_VER)
	$(Q)mkdir -p $(ROOTDIR)/skyline-apiserver
	$(Q)tar -xzf $(ROOTDIR)/skyline-apiserver-sdist/skyline_apiserver-$(SKYLINE_APISERVER_VER).tar.gz \
		--strip-components=1 -C $(ROOTDIR)/skyline-apiserver
	$(Q)set -e; for p in $$(find $(SKYLINE_PATCHDIR) -name '*.patch' 2>/dev/null | sort); do \
		rel=$${p#$(SKYLINE_PATCHDIR)/}; tgt=$(ROOTDIR)/skyline-apiserver/$${rel%.patch}; \
		echo "  PATCH $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "skyline: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done
	$(Q)chroot $(ROOTDIR) sh -c "cd /skyline-apiserver && $(SKYLINE_PIP) install $(SKYLINE_PIP_C) -r requirements.txt && $(SKYLINE_PIP) install $(SKYLINE_PIP_C) ."
	$(Q)cp ${ROOTDIR}/skyline-apiserver/etc/gunicorn.py ${ROOTDIR}/etc/skyline/gunicorn.py
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/skyline/skyline-apiserver.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/skyline/skyline.yaml.in .$(SKYLINE_CONF_DIR)/skyline.yaml.in
	$(Q)rm -rf $(ROOTDIR)/skyline-apiserver $(ROOTDIR)/skyline-apiserver-sdist

# skyline-console installation
#
# The console stays on the bigstack-oss fork: it is a React single-page app carrying
# well over a hundred of our commits, and pip is only its packaging -- the wheel holds
# the built static tree, which nginx serves straight out of the venv's site-packages.
# So it follows the apiserver into the epoxy venv without a version change; its pages
# talk to the service APIs directly through nginx, and those have been epoxy since #670.
rootfs_install::
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) uninstall -y skyline-console
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) cache remove skyline-console
	$(Q)for i in {1..3} ; do timeout 120 git clone --depth 1 https://github.com/bigstack-oss/skyline-console.git $(ROOTDIR)/skyline-console && break ; done
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(ROOTDIR)/skyline-console && nvm install $(QEND)
	$(Q)cd $(ROOTDIR)/skyline-console && nvm use $(QEND) && npm install -g yarn $(QEND)
	$(Q)cd $(ROOTDIR)/skyline-console && nvm use $(QEND) && make package
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV
	$(Q)chroot $(ROOTDIR) sh -c "cd /skyline-console && $(SKYLINE_PIP) install $(SKYLINE_PIP_C) dist/skyline_console-*.whl"
	$(Q)rm -rf $(ROOTDIR)/skyline-console

# for RC builds
heavyfs_install::
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) uninstall -y skyline-console
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) cache remove skyline-console
	$(Q)for i in {1..3} ; do timeout 120 git clone -b v3.1.20-rc1 --depth 1 https://github.com/bigstack-oss/skyline-console.git $(ROOTDIR)/skyline-console && break ; done
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(ROOTDIR)/skyline-console && nvm install $(QEND)
	$(Q)cd $(ROOTDIR)/skyline-console && nvm use $(QEND) && npm install -g yarn $(QEND)
	$(Q)cd $(ROOTDIR)/skyline-console && nvm use $(QEND) && make package
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV
	$(Q)chroot $(ROOTDIR) sh -c "cd /skyline-console && $(SKYLINE_PIP) install $(SKYLINE_PIP_C) dist/skyline_console-*.whl"
	$(Q)rm -rf $(ROOTDIR)/skyline-console
