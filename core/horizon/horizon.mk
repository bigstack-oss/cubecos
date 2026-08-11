# Cube SDK
# horizon installation

# https://releases.openstack.org/antelope/index.html#antelope-horizon
HORIZON_VER := 23.1.1

# Not in the antelope upper-constraints, so pinned here for reproducibility. This is
# also a source build (see core/mysql/mysql.mk), which is the other reason not to
# leave it floating.
MYSQLCLIENT_VER := 2.2.8

# The dashboard layout. These used to live in core/heavyfs/Makefile, from the days
# when the openstack-dashboard rpm made the application directory a shared concern;
# nothing outside this file reads them any more, so they belong here.
#
# $(HORIZON_APP_DIR) holds manage.py, the collected static tree and an
# openstack_dashboard symlink for compatibility. $(HORIZON_DIR) has to name the real
# package directory rather than that symlink: the symlink stores an absolute in-image
# path, so a plain cp from the build host would follow it out to the *host* root
# instead of into $(ROOTDIR).
HORIZON_APP_DIR := /usr/share/openstack-dashboard
HORIZON_VENV_SITE_PACKAGES := $(OPENSTACK_HOME_DIR)/lib/python$(PYTHON_VER)/site-packages
HORIZON_DIR := $(HORIZON_VENV_SITE_PACKAGES)/openstack_dashboard
HORIZON_ETCDIR := /etc/openstack-dashboard
HORIZON_POLICY_DIR := $(HORIZON_ETCDIR)/default_policies

HORIZON_THEME_DIR := $(HORIZON_DIR)/themes
CUBE_THEME_SRCDIR := $(COREDIR)/horizon/theme
CUBE_THEME_DSTDIR := $(HORIZON_THEME_DIR)/cube

HORIZON_LOG_DIR := /var/log/horizon
HORIZON_APP_STATE_DIR := /var/lib/openstack-dashboard

# The same site-packages directory as seen from the build host. Every dashboard plugin
# is pip installed by the component that owns it -- heat-dashboard by heat.mk,
# ironic-ui by ironic.mk, manila-ui by manila.mk, octavia-dashboard by octavia.mk, and
# designate/masakari/watcher/neutron-vpnaas from git by theirs -- and all of them land
# here for the collection step below to pick up.
HORIZON_VENV_SP := $(ROOTDIR)$(HORIZON_VENV_SITE_PACKAGES)

CUBE_THEME_SRCS := $(shell find $(CUBE_THEME_SRCDIR) -type f 2>/dev/null)

$(PROJ_HEAVYFS): $(COREDIR)/horizon/local_settings.in $(CUBE_THEME_SRCS)

# install horizon inside the python 3.10 virtual environment
#
# The rpms this replaces are openstack-dashboard, openstack-dashboard-theme and
# python3-django-horizon. Each dashboard plugin is pip installed by the component
# that owns it; registering the panels and running manage.py is this file's job, and
# horizon is built last so all of it happens once every plugin is in the venv.
#
# Two dependencies that are not horizon requirements and so have to be named:
#   - mysqlclient replaces the python3-mysqlclient rpm. local_settings.in uses
#     django.db.backends.mysql for the cached_db session store, and that backend
#     imports MySQLdb. PyMySQL is already in the venv but django 3.2 rejects it:
#     it wants MySQLdb >= 1.4.0 and PyMySQL reports 1.0.2.
#   - pymemcache backs the PyMemcacheCache cache backend. python-memcached is in
#     the venv already, but MemcachedCache is removed in django 4.1 and there is
#     no reason to move onto a dead backend now.
#
# These are two pip invocations rather than one because the two halves want opposite
# build environments, and a single command can only have one. See the note by the venv
# bootstrap in core/heavyfs/Makefile for the whole story.
rootfs_install::
	$(Q)# enable dns in the rootfs for downloading packages
	$(Q)cp -f /etc/resolv.conf $(ROOTDIR)/etc/
	$(Q)# horizon's sdist-only XStatic dependencies import a pkg_resources-declared
	$(Q)# namespace from setup.py, so they have to be built against this venv's
	$(Q)# setuptools 65.7.0 -- a current setuptools has no pkg_resources at all.
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			--no-build-isolation \
			horizon==$(HORIZON_VER)"
	$(Q)# mysqlclient is the counter-example: it is also a source build, but its
	$(Q)# pyproject.toml is newer than setuptools 65.7.0 can parse, so it keeps pip's
	$(Q)# default build isolation and gets a current setuptools of its own.
	$(Q)chroot $(ROOTDIR) bash -c "source /opt/openstack-antelope/bin/activate && \
		pip install -c $(OPENSTACK_INSTALLED_PIP_CONSTRAINT) \
			mysqlclient==$(MYSQLCLIENT_VER) \
			pymemcache"
	$(Q)# clean up dns configurations after downloading packages
	$(Q)rm -f $(ROOTDIR)/etc/resolv.conf

# lay out /usr/share/openstack-dashboard
#
# horizon and openstack_dashboard are symlinks into the venv rather than copies:
# gunicorn imports them from site-packages either way, so a copy would only go
# stale. The horizon symlink already worked this way when the target was python
# 3.9.
#
# manage.py is installed from this directory. The openstack-dashboard rpm shipped
# it; the horizon wheel does not, and there is no console_script equivalent.
#
# STATIC_ROOT is pinned to $(HORIZON_APP_DIR)/static in local_settings.in. Horizon
# would otherwise derive it from the package location and collect 51MB of static
# assets into the venv, where openstack-dashboard.conf does not alias it.
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(HORIZON_APP_DIR)
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/horizon/manage.py .$(HORIZON_APP_DIR)/manage.py
	$(Q)chroot $(ROOTDIR) chmod 755 $(HORIZON_APP_DIR)/manage.py
	$(Q)chroot $(ROOTDIR) ln -sfn $(HORIZON_VENV_SITE_PACKAGES)/horizon $(HORIZON_APP_DIR)/horizon
	$(Q)chroot $(ROOTDIR) ln -sfn $(HORIZON_DIR) $(HORIZON_APP_DIR)/openstack_dashboard

# settings
#
# The local_settings.py symlink is what makes settings.py's `from
# local.local_settings import *` pick up /etc/openstack-dashboard/local_settings.
# The rpm created the same link; nothing in the wheel does.
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(HORIZON_ETCDIR)
	$(Q)chroot $(ROOTDIR) ln -sfn $(HORIZON_ETCDIR)/local_settings $(HORIZON_DIR)/local/local_settings.py
	$(Q)cp -f $(COREDIR)/horizon/local_settings.in $(ROOTDIR)/$(HORIZON_ETCDIR)/
	$(Q)echo "AVAILABLE_THEMES = [ ('cube', 'Cube Theme', 'themes/cube') ]" >> $(ROOTDIR)/$(HORIZON_ETCDIR)/local_settings.in
	$(Q)echo "DEFAULT_THEME = 'cube'" >> $(ROOTDIR)/$(HORIZON_ETCDIR)/local_settings.in
	$(Q)# config_horizon.cpp regenerates local_settings from local_settings.in on
	$(Q)# every Commit(), so these build-time values never reach a running node.
	$(Q)# They do have to parse, though: collectstatic and compress below import
	$(Q)# the settings module, and PyMemcacheCache splits LOCATION on ":" where the
	$(Q)# MemcachedCache backend it replaces accepted anything.
	$(Q)sed \
		-e 's/@CONTROLLER@/localhost/' -e 's/@TIME_ZONE@/America\/New_York/' \
		-e 's/@SHARED_ID@/localhost/' -e "s/'@CACHE_SERVERS@'/'localhost:11211'/" \
		-e 's/@DOMAIN@/Default/' -e 's/@HORIZON_DB_PASSWORD@/horizon_dbpass/' \
		$(ROOTDIR)/$(HORIZON_ETCDIR)/local_settings.in > $(ROOTDIR)/$(HORIZON_ETCDIR)/local_settings

# cube theme
rootfs_install::
	$(Q)cp -rf $(CUBE_THEME_SRCDIR) $(ROOTDIR)/$(CUBE_THEME_DSTDIR)

# register every plugin's panels, settings snippets and policy files
#
# All of this is horizon's job rather than each component's, and horizon is built
# last, so by now every plugin is in the venv. Each file is taken out of
# site-packages -- i.e. out of the release that is actually installed, never out of a
# different one. designate 2023.1, for instance, dropped the
# `from designatedashboard import exceptions` block from its own enabled/*.py, and a
# stale copy breaks the import and takes down the whole dashboard rather than one
# panel.
#
# Notes on the less obvious entries:
#   - heat-dashboard's _1699_orchestration_settings.py and manila-ui's policy files
#     have to be here or horizon logs "No policy rules for service
#     'orchestration'/'share'" on every start and denies those panels.
#   - the policy yaml files go next to horizon's own because POLICY_FILES_PATH is
#     <openstack_dashboard>/conf; the snippets reference them by bare filename.
#   - manila-ui also ships a _90_manila_shares.py. core/manila's copy replaces it
#     under the same name and is deliberately applied last: it narrows
#     enabled_share_protocols to what the generic driver actually serves.
#   - ironic-ui and neutron-vpnaas-dashboard ship one enabled/*.py each and no policy
#     file.
#   - watcher_policy.json is json, not yaml. oslo.policy warns about that on load;
#     it is what watcher-dashboard 2023.1 ships.
rootfs_install::
	$(Q)mkdir -p $(ROOTDIR)/$(HORIZON_DIR)/local/enabled
	$(Q)mkdir -p $(ROOTDIR)/$(HORIZON_DIR)/local/local_settings.d
	$(Q)mkdir -p $(ROOTDIR)/$(HORIZON_DIR)/conf/default_policies
	$(Q)# heat-dashboard
	$(Q)cp -f $(HORIZON_VENV_SP)/heat_dashboard/enabled/_16[1-5]0_*.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)cp -f $(HORIZON_VENV_SP)/heat_dashboard/local_settings.d/_1699_orchestration_settings.py $(ROOTDIR)/$(HORIZON_DIR)/local/local_settings.d/
	$(Q)cp -f $(HORIZON_VENV_SP)/heat_dashboard/conf/heat_policy.yaml $(ROOTDIR)/$(HORIZON_DIR)/conf/
	$(Q)cp -f $(HORIZON_VENV_SP)/heat_dashboard/conf/default_policies/heat.yaml $(ROOTDIR)/$(HORIZON_DIR)/conf/default_policies/
	$(Q)# ironic-ui
	$(Q)cp -f $(HORIZON_VENV_SP)/ironic_ui/enabled/_2200_ironic.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)# manila-ui
	$(Q)cp -f $(HORIZON_VENV_SP)/manila_ui/local/enabled/*.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)cp -f $(HORIZON_VENV_SP)/manila_ui/conf/manila_policy.yaml $(ROOTDIR)/$(HORIZON_DIR)/conf/
	$(Q)cp -f $(HORIZON_VENV_SP)/manila_ui/conf/default_policies/manila.yaml $(ROOTDIR)/$(HORIZON_DIR)/conf/default_policies/
	$(Q)cp -f $(COREDIR)/manila/local/local_settings.d/_90_manila_shares.py $(ROOTDIR)/$(HORIZON_DIR)/local/local_settings.d/
	$(Q)# designate-dashboard
	$(Q)cp -f $(HORIZON_VENV_SP)/designatedashboard/enabled/_1710_project_dns_panel_group.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)cp -f $(HORIZON_VENV_SP)/designatedashboard/enabled/_1721_dns_zones_panel.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)cp -f $(HORIZON_VENV_SP)/designatedashboard/enabled/_1722_dns_reversedns_panel.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)# masakari-dashboard
	$(Q)cp -f $(HORIZON_VENV_SP)/masakaridashboard/local/enabled/_50_masakaridashboard.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)cp -f $(HORIZON_VENV_SP)/masakaridashboard/local/local_settings.d/_50_masakari.py $(ROOTDIR)/$(HORIZON_DIR)/local/local_settings.d/
	$(Q)cp -f $(HORIZON_VENV_SP)/masakaridashboard/conf/masakari_policy.yaml $(ROOTDIR)/$(HORIZON_DIR)/conf/
	$(Q)# watcher-dashboard
	$(Q)cp -f $(HORIZON_VENV_SP)/watcher_dashboard/local/enabled/_310*.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)cp -f $(HORIZON_VENV_SP)/watcher_dashboard/conf/watcher_policy.json $(ROOTDIR)/$(HORIZON_DIR)/conf/
	$(Q)# neutron-vpnaas-dashboard
	$(Q)cp -f $(HORIZON_VENV_SP)/neutron_vpnaas_dashboard/enabled/_7100_project_vpn_panel.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)# octavia-dashboard
	$(Q)cp -f $(HORIZON_VENV_SP)/octavia_dashboard/enabled/_1482_project_load_balancer_panel.py $(ROOTDIR)/$(HORIZON_DIR)/local/enabled/
	$(Q)cp -f $(HORIZON_VENV_SP)/octavia_dashboard/local_settings.d/_1499_load_balancer_settings.py $(ROOTDIR)/$(HORIZON_DIR)/local/local_settings.d/

# The yaml files under $(HORIZON_POLICY_DIR) that local_settings.in's
# DEFAULT_POLICY_FILES points at came from the openstack-dashboard rpm, and the
# masakari one from masakari.mk running this same command under python 3.9. Generate
# them all here instead, from the services that are actually running -- every one of
# these namespaces is an oslo.policy.policies entry point inside the venv, and
# manage.py only exists once the step above has installed it.
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 755 $(HORIZON_POLICY_DIR)
	$(Q)# || exit 1 per iteration: a for loop only returns the status of its *last*
	$(Q)# iteration, so without it a failure in any earlier namespace leaves an empty
	$(Q)# or missing yaml and the build still passes -- surfacing at runtime as
	$(Q)# "No policy rules for service '<x>'" and a denied panel. masakari.mk used to
	$(Q)# state this guarantee explicitly ("that command exits 1 and the build fails");
	$(Q)# folding the dump into a loop here is what dropped it.
	$(Q)for ns in keystone nova cinder glance neutron masakari octavia ; do \
		chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/python $(HORIZON_APP_DIR)/manage.py \
			dump_default_policies --namespace $$ns \
			--output-file $(HORIZON_POLICY_DIR)/$$ns.yaml 2>&1 > /dev/null || exit 1 ; \
	done

# gunicorn, the systemd unit and the httpd reverse proxy
rootfs_install::
	$(Q)chroot $(ROOTDIR) install -d -m 750 -o apache -g apache $(HORIZON_LOG_DIR)
	$(Q)chroot $(ROOTDIR) install -d -m 750 -o apache -g apache $(HORIZON_APP_STATE_DIR)
	$(Q)$(INSTALL_DATA) -f $(ROOTDIR) $(COREDIR)/horizon/gunicorn-config.py .$(HORIZON_ETCDIR)/gunicorn-config.py
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/horizon/openstack-dashboard.service ./lib/systemd/system
	$(Q)$(INSTALL_DATA) $(ROOTDIR) $(COREDIR)/horizon/openstack-dashboard.conf ./etc/httpd/conf.d/

rootfs_install::
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/python $(HORIZON_APP_DIR)/manage.py compilemessages 2>&1 > /dev/null
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/python $(HORIZON_APP_DIR)/manage.py collectstatic --noinput 2>&1 > /dev/null
	$(Q)chroot $(ROOTDIR) $(OPENSTACK_HOME_DIR)/bin/python $(HORIZON_APP_DIR)/manage.py compress --force 2>&1 > /dev/null
	$(Q)chroot $(ROOTDIR) chmod 755 -R $(HORIZON_APP_DIR)
	$(Q)chroot $(ROOTDIR) sh -c "chown root:apache -R $(HORIZON_POLICY_DIR)/*"
	$(Q)chroot $(ROOTDIR) sh -c "chmod 640 -R $(HORIZON_POLICY_DIR)/*"
	$(Q)chroot $(ROOTDIR) chown root:apache $(HORIZON_ETCDIR)/local_settings
	$(Q)chroot $(ROOTDIR) chmod 640 $(HORIZON_ETCDIR)/local_settings
