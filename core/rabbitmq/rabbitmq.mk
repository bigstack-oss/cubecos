# Cube SDK
# rabbitmq installation

ROOTFS_DNF += logrotate

# install erlang
rootfs_install::
	$(Q)# primary RabbitMQ signing key
	$(Q)chroot $(ROOTDIR) rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/rabbitmq-release-signing-key.asc'
	$(Q)# modern Erlang repository
	$(Q)chroot $(ROOTDIR) rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key'
	$(Q)cp -f $(COREDIR)/rabbitmq/erlang.repo $(ROOTDIR)/etc/yum.repos.d/
	$(Q)chroot $(ROOTDIR) dnf install -y erlang-24.3.4.15-1.el9.x86_64

# install rabbitmq
rootfs_install::
	$(Q)chroot $(ROOTDIR) rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key'
	$(Q)cp -f $(COREDIR)/rabbitmq/rabbitmq.repo $(ROOTDIR)/etc/yum.repos.d/
	$(Q)chroot $(ROOTDIR) dnf install -y rabbitmq-server-3.10.25-1.el8.noarch

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/epmd@.socket ./lib/systemd/system
	$(Q)chroot $(ROOTDIR) sh -c 'sed "s/\/var\/run\//\/run\//g" /usr/lib/tmpfiles.d/rabbitmq-server.conf > /etc/tmpfiles.d/rabbitmq-server.conf'
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/rabbitmq-server.service ./usr/lib/systemd/system
