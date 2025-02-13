# Cube SDK
# rabbitmq installation

ROOTFS_DNF += rabbitmq-server

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/epmd@.socket ./lib/systemd/system
	$(Q)chroot $(ROOTDIR) sh -c 'sed "s/\/var\/run\//\/run\//g" /usr/lib/tmpfiles.d/rabbitmq-server.conf > /etc/tmpfiles.d/rabbitmq-server.conf'
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/rabbitmq-server.service ./usr/lib/systemd/system
