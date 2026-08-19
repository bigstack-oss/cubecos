# Cube SDK
# openstack skyline installation

SKYLINE_CONF_DIR := /etc/skyline
SKYLINE_POLICY_DIR := $(SKYLINE_CONF_DIR)/policy
SKYLINE_APP_DIR := /var/lib/skyline
SKYLINE_LOG_DIR := /var/log/skyline

# skyline runs out of the caracal venv, not system python: our forks branch off
# upstream master at 4.0.1 (apiserver) and 4.0.0.0rc1 (console), so their dependency
# set is 2024.1 and does not belong in the antelope venv either. gunicorn and alembic
# come from skyline-apiserver's own requirements inside that venv, which is why
# ROOTFS_PIP_NC no longer carries gunicorn -- nothing else used the system copy.
SKYLINE_VENV := $(CARACAL_OPENSTACK_HOME_DIR)
SKYLINE_PIP := $(SKYLINE_VENV)/bin/pip
SKYLINE_PIP_C := -c $(CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT)

# skyline user/group/directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(SKYLINE_CONF_DIR) $(SKYLINE_POLICY_DIR) $(SKYLINE_APP_DIR) $(SKYLINE_LOG_DIR)

# for RC builds
heavyfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(SKYLINE_CONF_DIR) $(SKYLINE_POLICY_DIR) $(SKYLINE_APP_DIR) $(SKYLINE_LOG_DIR)

# note: ROOTFS_PIP_DL_FROM is not used since we clone source from master branch instead of targeted openstack branch (stable/yoga)
# note: `pip install .` replaces `python3 setup.py install` -- setuptools dropped the
# install command, and the venv is on a setuptools new enough to have removed it.
# skyline-apiserver installation
rootfs_install::
	$(Q)# the pip3 uninstall clears the legacy system python 3.9 copy: an RC build starts
	$(Q)# from a published rootfs that still carries one, and nothing points at it any more
	$(Q)chroot $(ROOTDIR) pip3 uninstall -y skyline-apiserver
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) uninstall -y skyline-apiserver
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) cache remove skyline-apiserver
	$(Q)for i in {1..3} ; do timeout 120 git clone --depth 1 https://github.com/bigstack-oss/skyline-apiserver.git $(ROOTDIR)/skyline-apiserver && break ; done
	$(Q)chroot $(ROOTDIR) sh -c "cd /skyline-apiserver && $(SKYLINE_PIP) install $(SKYLINE_PIP_C) -r requirements.txt && $(SKYLINE_PIP) install $(SKYLINE_PIP_C) ."
	$(Q)cp ${ROOTDIR}/skyline-apiserver/etc/gunicorn.py ${ROOTDIR}/etc/skyline/gunicorn.py
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/skyline/skyline-apiserver.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/skyline/skyline.yaml.in .$(SKYLINE_CONF_DIR)/skyline.yaml.in
	$(Q)rm -rf $(ROOTDIR)/skyline-apiserver

# for RC builds
heavyfs_install::
	$(Q)chroot $(ROOTDIR) pip3 uninstall -y skyline-apiserver
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) uninstall -y skyline-apiserver
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) cache remove skyline-apiserver
	$(Q)for i in {1..3} ; do timeout 120 git clone -b v3.1.10-rc1 --depth 1 https://github.com/bigstack-oss/skyline-apiserver.git $(ROOTDIR)/skyline-apiserver && break ; done
	$(Q)chroot $(ROOTDIR) sh -c "cd /skyline-apiserver && $(SKYLINE_PIP) install $(SKYLINE_PIP_C) -r requirements.txt && $(SKYLINE_PIP) install $(SKYLINE_PIP_C) ."
	$(Q)cp ${ROOTDIR}/skyline-apiserver/etc/gunicorn.py ${ROOTDIR}/etc/skyline/gunicorn.py
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/skyline/skyline-apiserver.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/skyline/skyline.yaml.in .$(SKYLINE_CONF_DIR)/skyline.yaml.in
	$(Q)rm -rf $(ROOTDIR)/skyline-apiserver

# skyline-console installation
rootfs_install::
	$(Q)chroot $(ROOTDIR) pip3 uninstall -y skyline-console
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
	$(Q)chroot $(ROOTDIR) pip3 uninstall -y skyline-console
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) uninstall -y skyline-console
	$(Q)chroot $(ROOTDIR) $(SKYLINE_PIP) cache remove skyline-console
	$(Q)for i in {1..3} ; do timeout 120 git clone -b v3.1.10-rc1 --depth 1 https://github.com/bigstack-oss/skyline-console.git $(ROOTDIR)/skyline-console && break ; done
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)cd $(ROOTDIR)/skyline-console && nvm install $(QEND)
	$(Q)cd $(ROOTDIR)/skyline-console && nvm use $(QEND) && npm install -g yarn $(QEND)
	$(Q)cd $(ROOTDIR)/skyline-console && nvm use $(QEND) && make package
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV
	$(Q)chroot $(ROOTDIR) sh -c "cd /skyline-console && $(SKYLINE_PIP) install $(SKYLINE_PIP_C) dist/skyline_console-*.whl"
	$(Q)rm -rf $(ROOTDIR)/skyline-console
