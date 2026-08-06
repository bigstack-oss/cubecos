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
OPENSTACK_RELEASE := yoga
RHOSP_RELEASE := 19
OPS_GITHUB_BRANCH := stable/yoga
OPS_GITHUB_TAG := yoga-eol
PYTHON_VER := 3.9

# pip contraints file
PROJ_PIP_CONSTRAINT ?= $(COREDIR)/heavyfs/os-$(OPENSTACK_RELEASE)-pip-upper-constraints.txt

# openstack next version
NEXT_OPENSTACK_RELEASE := antelope
NEXT_OPENSTACK_HOME_DIR := /opt/openstack-antelope
NEXT_OPS_GITHUB_BRANCH_01 := stable/2023.1
NEXT_OPS_GITHUB_BRANCH_02 := unmaintained/2023.1
NEXT_PYTHON_VER := 3.10
NEXT_OPENSTACK_PIP_CONSTRAINT ?= $(COREDIR)/heavyfs/os-$(NEXT_OPENSTACK_RELEASE)-pip-upper-constraints.txt
NEXT_OPENSTACK_INSTALLED_PIP_CONSTRAINT := $(NEXT_OPENSTACK_HOME_DIR)/os-$(NEXT_OPENSTACK_RELEASE)-pip-upper-constraints.txt

# openstack caracal -- a second isolated runtime, kept apart from the antelope venv so
# that caracal-era components do not drag their dependency versions into the 2023.1
# services. skyline is the first occupant: its forks branch off upstream master at
# 4.0.1 (apiserver) and 4.0.0.0rc1 (console), i.e. caracal, not antelope.
CARACAL_OPENSTACK_RELEASE := caracal
CARACAL_OPENSTACK_HOME_DIR := /opt/openstack-$(CARACAL_OPENSTACK_RELEASE)
CARACAL_OPS_GITHUB_BRANCH_01 := stable/2024.1
CARACAL_OPS_GITHUB_BRANCH_02 := unmaintained/2024.1
CARACAL_PYTHON_VER := 3.11
CARACAL_PYTHON_PATCH_VER := 3.11.15
CARACAL_OPENSTACK_PIP_CONSTRAINT ?= $(COREDIR)/heavyfs/os-$(CARACAL_OPENSTACK_RELEASE)-pip-upper-constraints.txt
CARACAL_OPENSTACK_INSTALLED_PIP_CONSTRAINT := $(CARACAL_OPENSTACK_HOME_DIR)/os-$(CARACAL_OPENSTACK_RELEASE)-pip-upper-constraints.txt
