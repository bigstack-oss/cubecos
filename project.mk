# Core SDK

# support directory
COREDIR := $(TOP_SRCDIR)/core
CORE_MAINDIR  := $(COREDIR)/main

# core deliverables
CORE_SHIPDIR  := $(TOP_BLDDIR)/core/main/ship
CORE_USB      := $(CORE_SHIPDIR)/../proj.img
CORE_LIVE_USB := $(CORE_SHIPDIR)/../live_proj.img
CORE_PXE      := $(CORE_SHIPDIR)/../proj.pxe.tgz
CORE_PKGDIR   := $(COREDIR)/pkg

# core specific modules
PROJ_MODDIR := $(TOP_BLDDIR)/core/modules

# Node config namespace: the installer (hex) drops the phone-home agent's env
# file here (overrides hex's default).
HEX_AGENT_ENV_DIR := /etc/cube

# policy source tree
CORE_POLICYDIR := $(COREDIR)/policies

# cubecos shared build envs
GOLANG_VERSION := 1.24.2
PROJ_NFS_SERVER := 10.32.0.200
PROJ_NFS_CUBECOS_PATH := /volume1/bigstack/cube-images
PROJ_NFS_OPENSTACK_PATH := /volume1/docker/minio/downloads
PROJ_NFS_PATH := /volume1/pxe-server

PROJ_TEST_EXPORTS := "PS4=+[\\t]"

# openstack version
OPENSTACK_RELEASE := caracal
OPENSTACK_HOME_DIR := /opt/openstack-$(OPENSTACK_RELEASE)
OPS_GITHUB_BRANCH_01 := stable/2024.1
OPS_GITHUB_BRANCH_02 := unmaintained/2024.1
PYTHON_VER := 3.11
PYTHON_PATCH_VER := 3.11.15
OPENSTACK_PIP_CONSTRAINT ?= $(COREDIR)/heavyfs/os-$(OPENSTACK_RELEASE)-pip-upper-constraints.txt
OPENSTACK_INSTALLED_PIP_CONSTRAINT := $(OPENSTACK_HOME_DIR)/os-$(OPENSTACK_RELEASE)-pip-upper-constraints.txt

# The system python 3.9 pip constraint, for the ROOTFS_PIP installs in core/heavyfs
# and friends. Deliberately NOT os-$(OPENSTACK_RELEASE)-pip-upper-constraints.txt any
# more: no openstack package is installed into the system python since the antelope
# migration, and this file has been maintained locally instead -- it carries the CVE
# pins the ROOTFS_PIP lines exist for (pillow 11.3.0, waitress 3.0.2, numpy 1.25.2,
# ansible-core, python-jose, numexpr, xmlsec), none of which the openstack constraint
# files have. Deriving it from the release name would have quietly downgraded pillow
# to 9.2.0 and waitress to 2.1.2 -- straight back into CVE-2023-50447 and
# CVE-2024-49768 -- the moment OPENSTACK_RELEASE moved to antelope, and the same
# holds for every hop after it. This pin does not follow the release name, ever.
PROJ_PIP_CONSTRAINT ?= $(COREDIR)/heavyfs/rootfs-pip-constraints.txt

# openstack next version -- left blank until the next hop, then filled in the way
# antelope's were while it was NEXT_*: a second venv is built from these, components
# move into it one at a time, and the values are promoted above once the move is done.
NEXT_OPENSTACK_RELEASE :=
NEXT_OPENSTACK_HOME_DIR :=
NEXT_OPS_GITHUB_BRANCH_01 :=
NEXT_OPS_GITHUB_BRANCH_02 :=
NEXT_PYTHON_VER :=
NEXT_OPENSTACK_PIP_CONSTRAINT ?=
NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT :=

# The caracal hop is complete -- the block above IS caracal now, and there is no second
# runtime. /opt/openstack-caracal on python 3.11 was built alongside the antelope venv
# so that caracal-era components would not drag their dependency versions into the
# 2023.1 services, and the services moved into it one at a time:
#
#   skyline (first, its forks branch off upstream master at 4.0.1 / 4.0.0.0rc1, i.e.
#   caracal rather than antelope), keystone 25.0.0 (#631), glance 28.2.0 (#630),
#   cinder 24.5.0 (#629), nova with placement 29.4.0 / 11.0.1 (#627),
#   neutron 24.2.2 (#628), manila 18.3.0 (#638), octavia 14.0.2 (#640),
#   barbican 18.0.0 (#632), cyborg 12.0.0 (#633), designate 18.0.0 (#634),
#   heat 22.0.1 (#635), ironic with ironic-inspector 24.1.5 / 12.1.1 (#637),
#   masakari with masakari-monitors 17.0.0 / 17.0.1 (#639), watcher 12.1.0 (#643)
#   and horizon 24.0.2 (#636), which took the eight dashboard plugins and the
#   openstack cli with it.
#
# The ordinals are merge order into develop; #642 moved python-swiftclient rather than
# a service, so it takes no place in that count.
#
# Several hops had to leave a piece behind: an osc plugin is a stevedore entry point,
# visible only to the interpreter that runs /usr/bin/openstack, so barbican, designate,
# masakari, octavia, watcher, cyborg, heat and manila each left their client in the
# antelope venv, and designate, masakari, watcher and neutron-vpnaas left their horizon
# dashboard plugin there too. #636 collected all of it: horizon, the eight dashboard
# plugins, /usr/bin/openstack and the eight clients moved together.
#
# What was left after the services was not a service at all: monasca, retired by #672
# phase 4, and ospurge, moved into this venv by #625 -- which is what emptied the
# antelope venv, allowed its python 3.10 build to go, and let these values be promoted
# from CARACAL_* into the block above. Nothing is left on 3.10.
#
# $(OPS_GITHUB_BRANCH_02) has no reader in this tree -- the four dashboard clones were
# the last, and #636 took them -- but $(OPS_GITHUB_BRANCH_01) is still what
# core/heavyfs passes to PROJ_INSTALL_PIP, so the pair is left intact. Note that the
# ROOTFS_PIP entries it applies to name their own refs, so the branch is effectively
# unused there too; it is kept because the next hop will want the pair.
