# Cube SDK
# k3s installation

K3S_DIR := /opt/k3s/
INGRESS_NGINX_DIR := $(K3S_DIR)/ingress-nginx/
CEPH_CSI_DIR := $(K3S_DIR)/ceph-csi/

rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(K3S_DIR)
	$(Q)(cd $(TOP_BLDDIR)/core/k3s/ && cp -f k3s install.sh $(ROOTDIR)$(K3S_DIR))
	$(Q)cp -f $(COREDIR)/k3s/registries.yaml $(COREDIR)/k3s/remove_node.sh $(ROOTDIR)$(K3S_DIR)
	$(Q)cp -f /usr/local/bin/helm $(ROOTDIR)/usr/local/bin/
#	ingress-nginx
	$(Q)chroot $(ROOTDIR) mkdir -p $(INGRESS_NGINX_DIR)
	$(Q)cp -f $(COREDIR)/k3s/ingress-nginx/chart-values.yaml $(ROOTDIR)$(INGRESS_NGINX_DIR)
	$(Q)cp -f $(TOP_BLDDIR)/core/k3s/ingress-nginx/ingress-nginx-*.tgz $(ROOTDIR)$(INGRESS_NGINX_DIR)
#   ceph-csi
	$(Q)chroot $(ROOTDIR) mkdir -p $(CEPH_CSI_DIR)
	$(Q)cp -f $(TOP_BLDDIR)/core/k3s/ceph-csi/ceph-csi-*.tgz $(ROOTDIR)$(CEPH_CSI_DIR)
	$(Q)chroot $(ROOTDIR) ln -sf /usr/local/bin/k3s /usr/sbin/k3s
