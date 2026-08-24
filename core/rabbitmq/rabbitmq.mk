# Cube SDK
# rabbitmq installation

ROOTFS_DNF += logrotate

# rabbitmq-server 3.11 declares "erlang >= 25.0" and "erlang < 26.0" itself, so
# the erlang bump is mandatory rather than opportunistic. modern-erlang keeps
# exactly one 25.x build - 25.3.2.21 - next to the 26/27 it also serves, so pin
# it or a later dnf update lands on an erlang 3.11 refuses to run on
ERLANG_VER := 25.3.2.21-1.el9
LOCKED_DNF += erlang-$(ERLANG_VER)

# rabbitmq refuses to skip minor versions on upgrade, so 3.11 is the only step
# reachable from 3.10 - pin it against the 3.12/4.x the repo also serves.
# 3.11.28 is the last release of the 3.11 series
RABBITMQ_VER := 3.11.28-1.el8
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
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/rabbitmq-server.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/rabbitmq-server-overrides.conf ./etc/systemd/system/rabbitmq-server.service.d/
