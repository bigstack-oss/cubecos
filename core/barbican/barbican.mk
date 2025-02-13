# Cube SDK
# barbican installation

ROOTFS_DNF_NOARCH += openstack-barbican-api

BARBICAN_CONFDIR := $(ROOTDIR)/etc/barbican

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/barbican/barbican-wsgi.conf.in ./etc/httpd/conf.d/
	$(Q)cp -f $(BARBICAN_CONFDIR)/barbican.conf $(BARBICAN_CONFDIR)/barbican.conf.def
