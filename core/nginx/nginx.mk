# Cube SDK
# nginx installation

NGINX_CONF_DIR := /etc/nginx

ROOTFS_DNF += nginx

rootfs_install::
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/nginx/nginx.conf.in .$(NGINX_CONF_DIR)/nginx.conf.in
