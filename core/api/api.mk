# Cube SDK
# CubeCOS API installation

# api log
API_LOG_DIR := /var/log/cube-cos-api

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(API_LOG_DIR)

# api installation
API_RPM = $(TOP_BLDDIR)/core/api/api.rpm

rootfs_install::
	$(Q)cp -f $(API_RPM) $(ROOTDIR)/tmp
	$(Q)chroot $(ROOTDIR) dnf install -y /tmp/api.rpm
	$(Q)rm -rf /tmp/api.rpm
	$(Q)chroot $(ROOTDIR) systemctl disable cube-cos-api
	$(Q)cp -f $(COREDIR)/api/cube-cos-api.yaml.in $(ROOTDIR)/etc/cube/api

# for RC builds
heavyfs_install::
	$(Q)cp -f $(API_RPM) $(ROOTDIR)/tmp
	$(Q)chroot $(ROOTDIR) rpm -e cube-cos-api
	$(Q)chroot $(ROOTDIR) rpm -i /tmp/api.rpm
	$(Q)rm -rf /tmp/api.rpm
	$(Q)chroot $(ROOTDIR) systemctl disable cube-cos-api
	$(Q)cp -f $(COREDIR)/api/cube-cos-api.yaml.in $(ROOTDIR)/etc/cube/api
