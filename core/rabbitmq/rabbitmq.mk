# Cube SDK
# rabbitmq installation

ROOTFS_DNF += logrotate

# rabbitmq-server 3.12 declares "erlang >= 25.0" and "erlang < 27.0" itself, so
# 25 would still run it; 26 is taken now because 3.13, the next rung, runs on
# nothing older. 3.11 declares "erlang < 26.0", so erlang 26 cannot be rolled
# out ahead of the broker the way 25 was for 3.11 - the two move together.
# modern-erlang keeps two 26.x builds next to the 27s 3.12 refuses, so pin the
# later one
ERLANG_VER := 26.2.5.15-1.el9
LOCKED_DNF += erlang-$(ERLANG_VER)

# rabbitmq refuses to skip minor versions on upgrade, so 3.12 is the only step
# reachable from 3.11 - pin it against the 3.13/4.x the repo also serves.
# 3.12.14 is the last release of the 3.12 series
RABBITMQ_VER := 3.12.14-1.el8
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
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/epmd@.service ./lib/systemd/system
	$(Q)# listen from sockets.target on: any erl that runs before the socket does --
	$(Q)# rpm scriptlets and health checks call rabbitmqctl -- finds 4369 closed,
	$(Q)# spawns its own `epmd -daemon`, and the socket then cannot bind
	$(Q)chroot $(ROOTDIR) systemctl enable epmd@0.0.0.0.socket
	$(Q)chroot $(ROOTDIR) sh -c 'sed "s/\/var\/run\//\/run\//g" /usr/lib/tmpfiles.d/rabbitmq-server.conf > /etc/tmpfiles.d/rabbitmq-server.conf'
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/rabbitmq-server.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/rabbitmq/rabbitmq-server-overrides.conf ./etc/systemd/system/rabbitmq-server.service.d/
