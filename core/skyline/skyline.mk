# Cube SDK
# openstack skyline installation

SKYLINE_CONF_DIR := /etc/skyline
SKYLINE_POLICY_DIR := $(SKYLINE_CONF_DIR)/policy
SKYLINE_LOG_DIR := /var/log/skyline

# refer to skyline-apiserver/requirements.txt, need to be installed before openstack deps
ROOTFS_PIP_NC += gunicorn

# skyline user/group/directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(SKYLINE_CONF_DIR) $(SKYLINE_POLICY_DIR) $(SKYLINE_LOG_DIR)

# for RC builds
heavyfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(SKYLINE_CONF_DIR) $(SKYLINE_POLICY_DIR) $(SKYLINE_LOG_DIR)

# note: ROOTFS_PIP_DL_FROM is not used since we clone source from master branch instead of targeted openstack branch (stable/yoga)
# skyline-apiserver installation
rootfs_install::
	$(Q)chroot $(ROOTDIR) pip3 uninstall -y skyline-apiserver
	$(Q)chroot $(ROOTDIR) pip3 cache remove skyline-apiserver
	$(Q)for i in {1..10} ; do timeout 30 git clone --depth 1 https://github.com/bigstack-oss/skyline-apiserver.git $(ROOTDIR)/skyline-apiserver && break ; done
	$(Q)chroot $(ROOTDIR) sh -c "cd /skyline-apiserver && pip3 install -r requirements.txt && python3 setup.py install"
	$(Q)cp ${ROOTDIR}/skyline-apiserver/etc/gunicorn.py ${ROOTDIR}/etc/skyline/gunicorn.py
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/skyline/skyline-apiserver.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/skyline/skyline.yaml.in .$(SKYLINE_CONF_DIR)/skyline.yaml.in
	$(Q)rm -rf $(ROOTDIR)/skyline-apiserver

# for RC builds
heavyfs_install::
	$(Q)chroot $(ROOTDIR) pip3 uninstall -y skyline-apiserver
	$(Q)chroot $(ROOTDIR) pip3 cache remove skyline-apiserver
	$(Q)for i in {1..10} ; do timeout 30 git clone -b v3.0.0-rc4 --depth 1 https://github.com/bigstack-oss/skyline-apiserver.git $(ROOTDIR)/skyline-apiserver && break ; done
	$(Q)chroot $(ROOTDIR) sh -c "cd /skyline-apiserver && pip3 install -r requirements.txt && python3 setup.py install"
	$(Q)cp ${ROOTDIR}/skyline-apiserver/etc/gunicorn.py ${ROOTDIR}/etc/skyline/gunicorn.py
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/skyline/skyline-apiserver.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/skyline/skyline.yaml.in .$(SKYLINE_CONF_DIR)/skyline.yaml.in
	$(Q)rm -rf $(ROOTDIR)/skyline-apiserver

# skyline-console installation
rootfs_install::
	$(Q)chroot $(ROOTDIR) pip3 uninstall -y skyline-console
	$(Q)chroot $(ROOTDIR) pip3 cache remove skyline-console
	$(Q)for i in {1..10} ; do timeout 30 git clone --depth 1 https://github.com/bigstack-oss/skyline-console.git $(ROOTDIR)/skyline-console && break ; done
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)nvm use $(SKYLINE_NODE_VERSION) $(QEND) && make -C $(ROOTDIR)/skyline-console package
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV
	$(Q)chroot $(ROOTDIR) sh -c "cd /skyline-console && pip3 install dist/skyline_console-*.whl"
	$(Q)rm -rf $(ROOTDIR)/skyline-console

# for RC builds
heavyfs_install::
	$(Q)chroot $(ROOTDIR) pip3 uninstall -y skyline-console
	$(Q)chroot $(ROOTDIR) pip3 cache remove skyline-console
	$(Q)for i in {1..10} ; do timeout 30 git clone -b v3.0.0-rc4 --depth 1 https://github.com/bigstack-oss/skyline-console.git $(ROOTDIR)/skyline-console && break ; done
	$(Q)# enable nvm
	$(Q)sed -i 's/^#//g' $$BASH_ENV
	$(Q)nvm use $(SKYLINE_NODE_VERSION) $(QEND) && make -C $(ROOTDIR)/skyline-console package
	$(Q)# disable nvm
	$(Q)sed -i '/^#/! s/^/#/' $$BASH_ENV
	$(Q)chroot $(ROOTDIR) sh -c "cd /skyline-console && pip3 install dist/skyline_console-*.whl"
	$(Q)rm -rf $(ROOTDIR)/skyline-console
