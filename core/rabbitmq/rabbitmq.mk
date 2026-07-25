# Cube SDK
# rabbitmq installation

ROOTFS_DNF += logrotate

# erlang 26.2.5-1.el9 doesn't work with rabbitmq, and modern-erlang also serves
# 25/26/27 - pin what we install so a later dnf update can't bump it
ERLANG_VER := 24.3.4.15-1.el9
LOCKED_DNF += erlang-$(ERLANG_VER)

# rabbitmq refuses to skip minor versions on upgrade, so 3.10 is the only step
# reachable from 3.9 - pin it against the 3.11/3.12/4.x the repo also serves
RABBITMQ_VER := 3.10.25-1.el8
LOCKED_DNF += rabbitmq-server-$(RABBITMQ_VER)

# install erlang
rootfs_install::
	$(Q)# primary RabbitMQ signing key
	$(Q)chroot $(ROOTDIR) rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/rabbitmq-release-signing-key.asc'
	$(Q)# modern Erlang repository
	$(Q)chroot $(ROOTDIR) rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key'
	$(Q)cp -f $(COREDIR)/rabbitmq/erlang.repo $(ROOTDIR)/etc/yum.repos.d/
	$(Q)chroot $(ROOTDIR) dnf install -y erlang-$(ERLANG_VER).x86_64

# install rabbitmq
rootfs_install::
	$(Q)chroot $(ROOTDIR) rpm --import 'https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key'
	$(Q)cp -f $(COREDIR)/rabbitmq/rabbitmq.repo $(ROOTDIR)/etc/yum.repos.d/
	$(Q)chroot $(ROOTDIR) dnf install -y rabbitmq-server-$(RABBITMQ_VER).noarch

rootfs_install::
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/epmd@.socket ./lib/systemd/system
	$(Q)chroot $(ROOTDIR) sh -c 'sed "s/\/var\/run\//\/run\//g" /usr/lib/tmpfiles.d/rabbitmq-server.conf > /etc/tmpfiles.d/rabbitmq-server.conf'
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/rabbitmq-server.service ./usr/lib/systemd/system
