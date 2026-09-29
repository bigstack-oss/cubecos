# Cube SDK
# octavia installation

# python-octaviaclient owns the `loadbalancer` subcommand, a stevedore entry point.
# core/sdk_sh/modules/sdk_os.sh drives octavia entirely through it -- `loadbalancer
# list` (L404), the four flavorprofile/flavor pairs created at bootstrap
# (L1580-L1602) and `loadbalancer delete --cascade` (L1835) -- so without it the load
# balancer bootstrap and teardown paths break.
#
# It used to be the yoga python3-octaviaclient rpm under the *system* python 3.9,
# because /usr/bin/openstack was `#!/usr/bin/python3` and an entry point is only
# visible to the interpreter it was installed under. #1206 moved it into the antelope
# venv alongside the CLI. This rpm was also the only hard Requires on
# python3-openstackclient anywhere in the tree, so dropping it there is what let
# core/heavyfs stop installing the yoga CLI.
#
# It had to stay in the antelope venv when octavia moved to caracal, for that same
# entry-point reason -- the `loadbalancer` plugin has to be installed under whichever
# interpreter runs /usr/bin/openstack or the call sites above stop resolving. #636
# moved the CLI, so it was installed with the service from then on. Unlike manila,
# there is no second consumer: octavia ships no standalone CLI and nothing in hex_sdk
# runs one, so the client is installed once.
#
# The epoxy hop split them again: #667 moved the service to the epoxy venv and left
# the client in the caracal one, next to /usr/bin/openstack, in a block of its own.
# #662 moved the CLI to epoxy, so that block installs the client there now, 3.10.0
# beside the 16.1.0 api.
#
# NOTE: unlike heat, health_octavia_check() is *not* what depends on this.
# It checks systemd units, the blackbox_exporter probe of the API and the
# octavia-hm0 OVN port, never the OSC CLI -- so `cluster check` would have
# stayed green while the bootstrap paths above failed.
#
# openstack-octavia-ui, the Horizon dashboard plugin, is replaced by the
# octavia-dashboard wheel installed further down. It was dropped when octavia moved
# to pip because Horizon still ran on the system python 3.9 and could not import a
# package from a venv; #609 moved Horizon into the antelope venv, so the Load Balancer
# panel came back, #636 moved both to caracal and #662 to epoxy. Registering it is
# core/horizon's job, where every dashboard action lives.
#
# The octavia user and group are carried statically by
# core/heavyfs/account/centos9 (uid/gid 138), so the RDO spec's shadow-utils
# requirement has no equivalent here.

OCTAVIA_CONF_DIR := /etc/octavia
OCTAVIA_CONFDIR := $(ROOTDIR)$(OCTAVIA_CONF_DIR)

OCTAVIA_SRCDIR := $(ROOTDIR)$(NEXT_OPENSTACK_HOME_DIR)/lib/python$(NEXT_PYTHON_VER)/site-packages/octavia
OCTAVIA_PATCHDIR := $(COREDIR)/octavia/$(NEXT_OPENSTACK_RELEASE)_patch/octavia

# https://releases.openstack.org/epoxy/index.html#epoxy-octavia -- 16.1.0 is the newest
# 2025.1 release, the same "last numeric revision of the series" rule #1206 and #640
# used to land on 12.0.1 and 14.0.2. 16.1.0 over 16.0.1 carries three security fixes --
# HAProxy config injection through a listener's or pool's tls_ciphers and through an
# L7 policy's redirect_url / redirect_prefix, and a QoS policy of another project
# accepted on a VIP -- and upstream's own fix for the ZooKeeper session churn this tree
# used to carry a patch for. core/octavia/Makefile builds the amphora image from this
# same tag, so the agent inside the image and the controllers outside it stay one
# release.
OCTAVIA_VER := 16.1.0

# octavia-dashboard follows horizon, not the octavia service: it installs next to
# horizon because that is where collectstatic collects panels from. #662 moved horizon
# into the epoxy venv, so this moved with it. 15.0.1 is the newest epoxy release --
# https://releases.openstack.org/epoxy/index.html#epoxy-octavia-dashboard. It talks
# to the API over HTTP and imports nothing from octavia, which is why it could stay a
# release behind the service while horizon did. Horizon plugins are not in the
# upper-constraints (that file only covers libraries), so the pin is explicit.
OCTAVIA_DASHBOARD_VER := 15.0.1

# install octavia into the epoxy venv
#
# octavia runs out of the epoxy venv, not the caracal one it shares with the 2024.1
# services still there. It cannot be bumped in place: 16.x requires octavia-lib>=3.8.0
# and taskflow>=5.9.0, which os-caracal-pip-upper-constraints.txt holds at 3.5.0 and
# 5.6.0 for watcher, which stayed on 2024.1 until #670. So the service moves alone into
# $(NEXT_OPENSTACK_HOME_DIR), the same shape as its caracal hop (#640), one release on,
# after keystone, glance, cinder, nova/placement, neutron, barbican, cyborg, designate,
# heat, ironic, manila and masakari.
#
# The /usr/bin/octavia-* links follow the service: the four units, config_octavia.cpp
# and hex_sdk's migrate_octavia_db all reach octavia through them.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# octavia-lib is in octavia's requirements.txt now (>=3.8.0), and it is still
	$(Q)# named: the amphora provider driver imports it directly (octavia/api/drivers/
	$(Q)# amphora_driver/v2/driver.py imports octavia_lib.api.drivers), and that is
	$(Q)# the provider this deployment uses. The RPM pulled it in as
	$(Q)# python3-octavia-lib, and pip did not while the requirement was missing.
	$(Q)#
	$(Q)# kazoo is the same shape of problem, and the venv split is what exposed it.
	$(Q)# config_octavia.cpp writes task_flow/jobboard_backend_driver =
	$(Q)# zookeeper_taskflow_driver, and taskflow's zookeeper jobboard imports kazoo
	$(Q)# -- but that is an *extra* (taskflow[zookeeper]), not a requirement, and
	$(Q)# octavia does not declare it. Under antelope it happened to be present
	$(Q)# anyway, dragged into the shared venv by monasca-common; the caracal venv had
	$(Q)# no monasca, so octavia-worker crash-looped on ModuleNotFoundError: No module
	$(Q)# named 'kazoo' until this line existed. Named here rather than as
	$(Q)# taskflow[zookeeper] to match octavia-lib above, and because the constraint
	$(Q)# file already pins it (2.10.0).
	$(Q)#
	$(Q)# The other three are named for the same reason, because octavia's
	$(Q)# requirements.txt asks for none of them:
	$(Q)#   PyMySQL                config_octavia.cpp writes mysql+pymysql://
	$(Q)#                          connections for [database] and the taskflow
	$(Q)#                          persistence
	$(Q)#   oslo.messaging[kafka]  config_octavia.cpp points the notification
	$(Q)#                          transport at kafka://
	$(Q)#   python-memcached       config_octavia.cpp writes memcached_servers, which
	$(Q)#                          makes keystonemiddleware import memcache on its
	$(Q)#                          first token validation
	$(Q)# All five happen to be in this venv already, but a dependency nothing asks
	$(Q)# for is one that disappears silently.
	$(Q)chroot $(ROOTDIR) bash -c "source $(NEXT_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			octavia==$(OCTAVIA_VER) \
			octavia-lib \
			kazoo \
			PyMySQL \
			\"oslo.messaging[kafka]\" \
			python-memcached"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link the seven console scripts that run on the controller. The venv
	$(Q)# also gains amphora-agent, amphora-health-checker, amphora-interface,
	$(Q)# haproxy-vrrp-check and prometheus-proxy; those run *inside* the
	$(Q)# amphora VM and are provided by the amphora image, so they are left
	$(Q)# unlinked on purpose. octavia-wsgi, for serving the api under a wsgi
	$(Q)# container, is left unlinked too: octavia-api.service execs octavia-api
	$(Q)# directly. 2025.1 declares the same set as 2024.1.
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/octavia-api /usr/bin/octavia-api
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/octavia-worker /usr/bin/octavia-worker
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/octavia-health-manager /usr/bin/octavia-health-manager
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/octavia-housekeeping /usr/bin/octavia-housekeeping
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/octavia-db-manage /usr/bin/octavia-db-manage
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/octavia-driver-agent /usr/bin/octavia-driver-agent
	$(Q)chroot $(ROOTDIR) ln -sf $(NEXT_OPENSTACK_HOME_DIR)/bin/octavia-status /usr/bin/octavia-status

# the osc plugin
#
# python-octaviaclient owns the "loadbalancer" osc plugin, and sits in the epoxy venv
# next to /usr/bin/openstack -- see the note at the top. It is named explicitly
# because an entry point is only visible to the interpreter /usr/bin/openstack runs
# under, so a dependency nothing asks for is one that can disappear silently. No
# version is named: os-epoxy-pip-upper-constraints.txt already carries
# python-octaviaclient, so a version here could only drift from that file. It owns no
# console script, so nothing needs linking.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) bash -c "source $(NEXT_OPENSTACK_HOME_DIR)/bin/activate && \
		pip install -c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			python-octaviaclient"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# Whole-file downstream copies, if any -- anything under PATCHDIR that is not a
# *.py.patch or its *.py.orig. Nothing uses this today: both carried changes are
# unified diffs below.
rootfs_install::
	$(Q)[ -d $(OCTAVIA_PATCHDIR) ] && rsync -a --exclude='*.py.patch' --exclude='*.py.orig' $(OCTAVIA_PATCHDIR)/ $(OCTAVIA_SRCDIR)/ || /bin/true

# Reviewable unified diffs, same convention as core/masakari: each patch sits at
# <PATCHDIR>/<rel>.py.patch and targets <SRCDIR>/<rel>.py, with a <rel>.py.orig
# alongside for review only. Preferred over the whole-file copies above -- a diff
# shows what we changed, and --forward keeps re-runs idempotent while a failed
# hunk aborts the build, so upstream drift is caught here rather than shipped.
#
# Two are carried:
#
#   compute/drivers/nova_driver.py  meta={'HA_Enabled': 'False'} on the amphora
#                                   boot, so masakari does not evacuate amphorae
#   cmd/status.py                   import octavia.common.policy, which is what
#                                   registers the [oslo_policy] group that
#                                   _check_yaml_policy() reads. Without it
#                                   `octavia-status upgrade check` dies with
#                                   "NoSuchOptError: no such option oslo_policy in
#                                   group [DEFAULT]" before printing any result.
#                                   Still upstream's bug at 16.1.0 -- the import
#                                   list is unchanged since 12.0.1, and master's
#                                   is too. #1206 carried this as a whole-file
#                                   copy; a diff is what catches the next drift.
#
# Both apply to 16.1.0 unchanged. status.py is byte-identical to 14.0.2's, and
# nova_driver.py moved by one f-string conversion outside the hunk, so its .orig is
# refreshed and the .patch is a pure rename.
#
# caracal_patch/ also carried controller/worker/v2/taskflow_jobboard_driver.py, the
# backport of upstream's shared ZooKeeper client (#640). It is not carried at epoxy:
# upstream backported the same fix to stable/2025.1 as b16147c1 ("Fix ZooKeeper
# session churn in ZookeeperTaskFlowDriver"), released in 16.1.0, and its
# ZookeeperTaskFlowDriver is line for line the class the patch produced. It also has
# the controller worker and the consumer call the driver's new shutdown(), which the
# patch never did.
rootfs_install::
	$(Q)set -e; for p in $$(find $(OCTAVIA_PATCHDIR) -name '*.py.patch' 2>/dev/null | sort); do \
		rel=$${p#$(OCTAVIA_PATCHDIR)/}; tgt=$(OCTAVIA_SRCDIR)/$${rel%.patch}; \
		echo "  PATCH   $${rel%.patch}"; \
		patch --forward --no-backup-if-mismatch -r - "$$tgt" < "$$p" \
			|| { echo "octavia: failed to apply $$p to $$tgt" >&2; exit 1; }; \
	done

# install the octavia web ui plugin, the openstack-octavia-ui rpm's replacement.
# Registering its panel and settings snippet is core/horizon's job, where every
# dashboard action lives -- including the generated default_policies/octavia.yaml,
# because the snippet octavia-dashboard ships registers
# POLICY_FILES['load-balancer'] but no file to back it.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# --no-build-isolation because this pulls horizon; see core/heavyfs/Makefile.
	$(Q)chroot $(ROOTDIR) $(NEXT_OPENSTACK_HOME_DIR)/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		--no-build-isolation \
		octavia-dashboard==$(OCTAVIA_DASHBOARD_VER)
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# prepare the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/octavia
	$(Q)chroot $(ROOTDIR) mkdir -p /tmp/octavia

# stage the checked-in sample config, dist conf and systemd units
# NOTE: core/octavia/oslo-config-generator/octavia.conf is not staged. It is the
# input that produced octavia.conf.sample and is kept in the repo for the next
# release hop; the image has no use for it.
rootfs_install::
	$(Q)cp -f $(COREDIR)/octavia/octavia.conf.sample $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-dist.conf $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-api.service $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-worker.service $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-housekeeping.service $(ROOTDIR)/tmp/octavia/
	$(Q)cp -f $(COREDIR)/octavia/octavia-health-manager.service $(ROOTDIR)/tmp/octavia/

# install system directories and files
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 755 /usr/share/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/lib/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 750 /var/log/octavia
	$(Q)chroot $(ROOTDIR) install -d -m 755 /var/run/octavia
	$(Q)# per-service drop-in directories the systemd units pass with
	$(Q)# --config-dir; oslo.config fails to start if they do not exist.
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/common
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-api
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-worker
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-housekeeping
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/conf.d/octavia-health-manager
	$(Q)chroot $(ROOTDIR) install -p -D -m 640 /tmp/octavia/octavia.conf.sample /etc/octavia/octavia.conf
	$(Q)# No policy.yaml is installed: octavia runs its own default RBAC. #1206
	$(Q)# through #640 carried upstream's etc/policy/admin_or_owner-policy.yaml as
	$(Q)# /etc/octavia/policy.yaml, the same file the RPM delivered, because the
	$(Q)# default then was octavia's advanced RBAC, under which every non-admin call
	$(Q)# needed an explicit load-balancer_* role -- and CubeCOS grants none.
	$(Q)#
	$(Q)# 16.0.0 made keystone's default roles the default instead: a project's member
	$(Q)# reads and writes its own load balancers, a reader only reads them, and
	$(Q)# admin is admin. Those are the roles CubeCOS actually hands out --
	$(Q)# cube_admins and appfw project users hold admin, federated cube_users hold
	$(Q)# member -- so for every one of them the default answers exactly as the file
	$(Q)# did, and carrying it would only pin octavia to a posture upstream has left,
	$(Q)# which no other service's hop has done with its new defaults. Two principals
	$(Q)# lose what the file gave them: a reader-only user can no longer write, which
	$(Q)# is what the role means, and a user holding only the legacy _member_ role is
	$(Q)# refused, as nova's default already refuses it a server. That is the
	$(Q)# direction #216 set: member is the role upstream policy is written against,
	$(Q)# horizon hands it to new project users, and `hex_cli iaas identity
	$(Q)# migrate_legacy_member_role` grants it to every principal still holding only
	$(Q)# _member_, which is kept for old assignments and nothing new.
	$(Q)#
	$(Q)# oslo.policy treats a missing policy file as "use the registered defaults"
	$(Q)# and logs it at debug, and octavia-status's YAML Policy File check only
	$(Q)# reads the policy_file option's suffix, so neither notices it is gone.
	$(Q)# 644, not 640: the units run as User=octavia and must be able to read
	$(Q)# this. It holds no secrets.
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-dist.conf /usr/share/octavia/octavia-dist.conf
	$(Q)# certificate tooling (unchanged from the RPM layout)
	$(Q)chroot $(ROOTDIR) install -d -m 755 /etc/octavia/certs
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/certs/create_certificates.sh .$(OCTAVIA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/certs/octavia-certs.cnf .$(OCTAVIA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/octavia/dhclient.conf .$(OCTAVIA_CONF_DIR)
	$(Q)chroot $(ROOTDIR) chmod 755 /etc/octavia/create_certificates.sh
	$(Q)# install systemd unit files. All four are installed here now; under the
	$(Q)# RPM layout only worker and health-manager were, because
	$(Q)# openstack-octavia-{api,housekeeping} shipped the other two. The two
	$(Q)# units this branch rewrote are verbatim copies of the ones those RPMs
	$(Q)# installed, so dropping the RPMs does not change how they start. Note
	$(Q)# the checked-in files they replaced were never installed by anything --
	$(Q)# that is why they still pointed at /usr/local/bin.
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-api.service /usr/lib/systemd/system/octavia-api.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-worker.service /usr/lib/systemd/system/octavia-worker.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-housekeeping.service /usr/lib/systemd/system/octavia-housekeeping.service
	$(Q)chroot $(ROOTDIR) install -p -D -m 644 /tmp/octavia/octavia-health-manager.service /usr/lib/systemd/system/octavia-health-manager.service
	$(Q)# gate the health-manager on the planned-maintenance marker: it rebuilds every
	$(Q)# amphora on stale heartbeats, which a planned shutdown otherwise looks like
	$(Q)chroot $(ROOTDIR) mkdir -p /etc/systemd/system/octavia-health-manager.service.d
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/main/cube-planned-maintenance.conf ./etc/systemd/system/octavia-health-manager.service.d/

# adjust file ownerships and permissions
rootfs_install::
	$(Q)chroot $(ROOTDIR) chown root:octavia /etc/octavia/octavia.conf
	$(Q)chroot $(ROOTDIR) chmod 0640 /etc/octavia/octavia.conf
	$(Q)chroot $(ROOTDIR) chown octavia:octavia /var/lib/octavia
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/lib/octavia
	$(Q)chroot $(ROOTDIR) chown octavia:octavia /var/log/octavia
	$(Q)chroot $(ROOTDIR) chmod 0750 /var/log/octavia
	$(Q)chroot $(ROOTDIR) chown octavia:octavia /var/run/octavia
	$(Q)chroot $(ROOTDIR) chmod 0755 /var/run/octavia

# clean up the build directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -rf /tmp/octavia

# hex_config reads this baseline and regenerates /etc/octavia/octavia.conf from
# it, so it has to be taken after the install step above has replaced the file
# the RPMs used to provide.
rootfs_install::
	$(Q)cp -f $(OCTAVIA_CONFDIR)/octavia.conf $(OCTAVIA_CONFDIR)/octavia.conf.def
