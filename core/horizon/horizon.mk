# Cube SDK
# horizon installation

ROOTFS_DNF += python3-mysqlclient
ROOTFS_DNF_NOARCH +=  openstack-dashboard
HORIZON_THEME_DIR := $(HORIZON_DIR)/themes
CUBE_THEME_SRCDIR := $(COREDIR)/horizon/theme
CUBE_THEME_DSTDIR := $(HORIZON_THEME_DIR)/cube


# Red Hat Common User Experience (RCUE) https://github.com/redhat-rcue/rcue
RCUE_THEME_DSTDIR := $(HORIZON_THEME_DIR)/rcue

CUBE_THEME_SRCS := $(shell find $(CUBE_THEME_SRCDIR) -type f 2>/dev/null)

$(PROJ_HEAVYFS): $(COREDIR)/horizon/local_settings.in $(CUBE_THEME_SRCS)

rootfs_install::
# FIXME:
#	$(Q)cd $(ROOTDIR) && rpm2cpio $(BLDDIR)/RPMS/openstack-dashboard-$(RHOSP_RELEASE)*.rpm | cpio -idmv "*/locale/*"
	$(Q)chroot $(ROOTDIR) ln -sf /usr/local/lib/python3.9/site-packages/horizon /usr/share/openstack-dashboard/horizon
	$(Q)mkdir -p $(ROOTDIR)/$(HORIZON_DIR)/conf
	$(Q)cp -f $(ROOTDIR)/$(HORIZON_ETCDIR)/local_settings $(ROOTDIR)/$(HORIZON_ETCDIR)/local_settings.orig
	$(Q)cp -f $(ROOTDIR)/etc/httpd/conf.d/openstack-dashboard.conf $(ROOTDIR)/etc/httpd/conf.d/openstack-dashboard.conf.orig
	$(Q)cp -f $(COREDIR)/horizon/local_settings.in $(ROOTDIR)/$(HORIZON_ETCDIR)/
	$(Q)cp -f $(COREDIR)/horizon/openstack-dashboard.conf $(ROOTDIR)/etc/httpd/conf.d/
	$(Q)echo "AVAILABLE_THEMES = [ ('cube', 'Cube Theme', 'themes/cube') ]" >> $(ROOTDIR)/$(HORIZON_ETCDIR)/local_settings.in
	$(Q)echo "DEFAULT_THEME = 'cube'" >> $(ROOTDIR)/$(HORIZON_ETCDIR)/local_settings.in
	$(Q)sed \
		-e 's/@CONTROLLER@/localhost/' -e 's/@TIME_ZONE@/America\/New_York/' \
		$(ROOTDIR)/$(HORIZON_ETCDIR)/local_settings.in > $(ROOTDIR)/$(HORIZON_ETCDIR)/local_settings

rootfs_install::
	$(Q)cp -rf $(CUBE_THEME_SRCDIR) $(ROOTDIR)/$(CUBE_THEME_DSTDIR)

rootfs_install::
	$(Q)chroot $(ROOTDIR) python3 /usr/share/openstack-dashboard/manage.py compilemessages 2>&1 > /dev/null
	$(Q)chroot $(ROOTDIR) python3 /usr/share/openstack-dashboard/manage.py collectstatic --noinput 2>&1 > /dev/null
	$(Q)chroot $(ROOTDIR) python3 /usr/share/openstack-dashboard/manage.py compress --force 2>&1 > /dev/null
	$(Q)chroot $(ROOTDIR) chmod 755 -R /usr/share/openstack-dashboard
	$(Q)chroot $(ROOTDIR) sh -c "chown root:apache -R /etc/openstack-dashboard/default_policies/*"
	$(Q)chroot $(ROOTDIR) sh -c "chmod 640 -R /etc/openstack-dashboard/default_policies/*"
