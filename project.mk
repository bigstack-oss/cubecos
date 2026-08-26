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
# Installer disk auto-detect: skip our OSD/data disks (cube_ partition labels).
# SAN LUNs (Compellent, etc.) are excluded by hex's default transport filter.
HEX_INSTALL_DATA_LABEL_PREFIX := cube_

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
OPENSTACK_RELEASE := antelope
OPENSTACK_HOME_DIR := /opt/openstack-$(OPENSTACK_RELEASE)
OPS_GITHUB_BRANCH_01 := stable/2023.1
OPS_GITHUB_BRANCH_02 := unmaintained/2023.1
PYTHON_VER := 3.10
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
# CVE-2024-49768 -- the moment OPENSTACK_RELEASE moved to antelope.
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

# openstack caracal -- a second isolated runtime, kept apart from the antelope venv so
# that caracal-era components do not drag their dependency versions into the 2023.1
# services. skyline was the first occupant: its forks branch off upstream master at
# 4.0.1 (apiserver) and 4.0.0.0rc1 (console), i.e. caracal, not antelope. keystone
# (25.0.0) is the second -- #631, the first openstack service to make the hop -- and
# glance (28.2.0) the third (#630), cinder (24.5.0) the fourth (#629), nova with
# placement (29.4.0 / 11.0.1) the fifth (#627), neutron (24.2.2) the sixth (#628),
# manila (18.3.0) the seventh (#638) and barbican (18.0.0) the eighth (#632). The
# services move one at a time and OPENSTACK_RELEASE is promoted once they all have.
#
# barbican is the first of them to leave a piece behind: python-barbicanclient owns the
# `openstack secret ...` commands and has to stay in the antelope venv for as long as
# /usr/bin/openstack does. See core/barbican/barbican.mk.
CARACAL_OPENSTACK_RELEASE := caracal
CARACAL_OPENSTACK_HOME_DIR := /opt/openstack-$(CARACAL_OPENSTACK_RELEASE)
CARACAL_OPS_GITHUB_BRANCH_01 := stable/2024.1
CARACAL_OPS_GITHUB_BRANCH_02 := unmaintained/2024.1
CARACAL_PYTHON_VER := 3.11
CARACAL_PYTHON_PATCH_VER := 3.11.15
CARACAL_OPENSTACK_PIP_CONSTRAINT ?= $(COREDIR)/heavyfs/os-$(CARACAL_OPENSTACK_RELEASE)-pip-upper-constraints.txt
CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT := $(CARACAL_OPENSTACK_HOME_DIR)/os-$(CARACAL_OPENSTACK_RELEASE)-pip-upper-constraints.txt
