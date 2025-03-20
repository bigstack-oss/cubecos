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

# web source tree
CORE_WEBAPPDIR := $(COREDIR)/webapp

# cubecos shared build envs
RPMBUILD_DIR := /root/rpmbuild
GOLANG_VERSION := 1.24.0
UI_NODE_VERSION := 22.14.0
LMI_NODE_VERSION := 12.22.12
PROJ_NFS_SERVER := 10.32.0.200
PROJ_NFS_CUBECOS_PATH := /volume1/bigstack/cube-images
PROJ_NFS_OPENSTACK_PATH := /volume1/openstack-images
PROJ_NFS_PATH := /volume1/pxe-server

PROJ_TEST_EXPORTS := "PS4=+[\\t]"

# openstack version
OPENSTACK_RELEASE := yoga
RHOSP_RELEASE := 19
OPS_GITHUB_BRANCH := stable/yoga
PYTHON_VER := 3.9

# pip contraints file
PROJ_PIP_CONSTRAINT ?= $(COREDIR)/heavyfs/os-$(OPENSTACK_RELEASE)-pip-upper-constraints.txt
