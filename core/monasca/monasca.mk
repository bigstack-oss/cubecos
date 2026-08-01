# Cube SDK
# monasca installation

MONASCA_CONF_DIR := /etc/monasca
MONASCA_APP_DIR := /var/lib/monasca
MONASCA_LOG_DIR := /var/log/monasca
MONASCA_RUN_DIR := /var/run/monasca

MONASCA_SRCDIR := $(ROOTDIR)/opt/openstack-antelope/lib/python$(NEXT_PYTHON_VER)/site-packages
MONASCA_PATCHDIR := $(COREDIR)/monasca/$(NEXT_OPENSTACK_RELEASE)_patch

# NOTE: despite living alongside the antelope services, monasca is NOT installed
# from OpenStack Antelope (2023.1). The versions used are the Bobcat (2023.2)
# ones, which is where every monasca deliverable reached end of life -- upstream
# published nothing after it. CubeCOS has shipped them since the log4j hardening
# pass, so pinning to antelope would be a downgrade of the services:
#
#                         antelope 2023.1   bobcat 2023.2 (used here)
#   monasca-api                    10.0.0   11.0.0
#   monasca-common                  3.7.0   3.8.0
#   monasca-statsd                  2.6.0   2.7.0
#   python-monascaclient            2.7.0   2.8.0
#
# monasca-agent and monasca-persister were never cycle-managed; 10.0.0 and 9.0.0
# are their final PyPI releases and upstream lists them in neither cycle.
#
# monasca-common, monasca-statsd and python-monascaclient are version-controlled
# through os-antelope-pip-upper-constraints.txt, which carries their bobcat
# versions; pinning them again here would conflict with it. The three below are
# absent from that file -- upper-constraints only tracks libraries and clients,
# not the services -- so they are pinned at the install.
MONASCA_API_VER := 11.0.0
MONASCA_AGENT_VER := 10.0.0
MONASCA_PERSISTER_VER := 9.0.0

# FIXME: drop once watcher moves into the antelope venv. watcher is still the
# python 3.9 rpm under /usr/lib/python3.9, and watcher/common/clients.py does
# "from monascaclient import client" for the monasca datasource that
# config_watcher.cpp selects. Nothing else needs monasca in the system python.
# Version comes from the yoga constraint file (2.5.0), unchanged by the venv
# move; the venv gets the bobcat client from the antelope constraint file.
ROOTFS_PIP += python-monascaclient

# intel-cmt-cat provides pqos, used by the rdt_l3 agent plugin for per-VM L3
# cache occupancy. Installed via the centralized dnf pass in core/heavyfs.
ROOTFS_DNF += intel-cmt-cat

# monasca user/group/directory
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(MONASCA_CONF_DIR) $(MONASCA_APP_DIR) $(MONASCA_LOG_DIR) $(MONASCA_RUN_DIR)
	$(Q)chroot $(ROOTDIR) chown monasca:monasca $(MONASCA_CONF_DIR) $(MONASCA_APP_DIR) $(MONASCA_LOG_DIR) $(MONASCA_RUN_DIR)

# install monasca inside the python 3.10 virtual environment
# gunicorn: monasca-api is served by gunicorn now, see monasca-api.service
# influxdb: the persister's influxdb repository is an extra rather than a
#           requirement, and it is the backend config_monasca.cpp writes into
#           persister.conf
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)chroot $(ROOTDIR) /opt/openstack-antelope/bin/pip install \
		-c $(NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
		monasca-api==$(MONASCA_API_VER) \
		monasca-agent==$(MONASCA_AGENT_VER) \
		monasca-persister==$(MONASCA_PERSISTER_VER) \
		monasca-common \
		monasca-statsd \
		python-monascaclient \
		gunicorn \
		influxdb
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf
	$(Q)# Link binaries. monasca-setup derives its prefix from
	$(Q)# realpath(sys.argv[0]), so invoking it through this symlink still
	$(Q)# resolves its templates and generates its units against the venv.
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/monasca /usr/bin/monasca
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/monasca-api /usr/bin/monasca-api
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/monasca-api-wsgi /usr/bin/monasca-api-wsgi
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/monasca-collector /usr/bin/monasca-collector
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/monasca-forwarder /usr/bin/monasca-forwarder
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/monasca-persister /usr/bin/monasca-persister
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/monasca-setup /usr/bin/monasca-setup
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/monasca-statsd /usr/bin/monasca-statsd
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/monasca-status /usr/bin/monasca-status
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/monasca_db /usr/bin/monasca_db
	$(Q)# The system python still holds python-monascaclient for watcher, and
	$(Q)# /usr/local/bin precedes /usr/bin in PATH, so its 2.5.0 console script
	$(Q)# would shadow the venv client for anything calling a bare "monasca"
	$(Q)# (sdk_os.sh metric-name-list, operators). Point it at the venv one; the
	$(Q)# library itself stays importable where watcher needs it. Drop together
	$(Q)# with the ROOTFS_PIP entry above.
	$(Q)chroot $(ROOTDIR) ln -sf /opt/openstack-antelope/bin/monasca /usr/local/bin/monasca

# monasca-persister
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -f $(MONASCA_CONF_DIR)/persister-logging.conf
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/persister/persister-logging.conf .$(MONASCA_CONF_DIR)
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/monasca/persister/persister.conf .$(MONASCA_CONF_DIR)/persister.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/persister/monasca-persister.service ./lib/systemd/system

# monasca-api
rootfs_install::
	$(Q)chroot $(ROOTDIR) rm -f $(MONASCA_CONF_DIR)/api-config.ini $(MONASCA_CONF_DIR)/api-logging.conf
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/api/api-config.ini .$(MONASCA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/api/api-logging.conf .$(MONASCA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/api/gunicorn-config.py .$(MONASCA_CONF_DIR)
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/monasca/api/api-config.conf .$(MONASCA_CONF_DIR)/api-config.conf.def
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/api/monasca-mysql.sql .$(MONASCA_CONF_DIR)
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/api/monasca-api.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/api/monasca-api-wsgi.conf.in ./etc/httpd/conf.d/

# monasca-agent
rootfs_install::
	$(Q)chroot $(ROOTDIR) mkdir -p $(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/monasca-collector.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/monasca-forwarder.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/agent.yaml.in .$(MONASCA_CONF_DIR)/agent
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/conf.d.in/haproxy.yaml.in .$(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/conf.d.in/libvirt.yaml.in .$(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/conf.d.in/mcache.yaml.in .$(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/conf.d.in/http_check.yaml.in .$(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/conf.d.in/ipmi_sensors.yaml.in .$(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/conf.d.in/rdt_l3.yaml.in .$(MONASCA_CONF_DIR)/agent/conf.d.in
	$(Q)chroot $(ROOTDIR) chmod 644 $(MONASCA_CONF_DIR)/agent/conf.d.in

rootfs_install::
	$(Q)[ -d $(MONASCA_PATCHDIR) ] && cp -rf $(MONASCA_PATCHDIR)/* $(MONASCA_SRCDIR)/ || /bin/true
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/monasca/agent/monasca-agent.sudoers ./etc/sudoers.d/monasca-agent
	$(Q)chroot $(ROOTDIR) chmod 440 /etc/sudoers.d/monasca-agent

rootfs_install::
	$(Q)$(COREDIR)/monasca/santize-monasca-log4j.sh $(BLDDIR)/heavy_rootfs/opt/openstack-antelope/lib/python$(NEXT_PYTHON_VER)/site-packages/monasca_agent/collector/checks/libs
