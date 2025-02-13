# Core SDK

# support directory
COREDIR := $(TOP_SRCDIR)/core
CORE_MAINDIR  := $(COREDIR)/main

# Core deliverables
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

PROJ_TEST_EXPORTS := "PS4=+[\\t]"

# openstack version
OPENSTACK_RELEASE := yoga
RHOSP_RELEASE := 19
OPS_GITHUB_BRANCH := stable/yoga
PYTHON_VER := 3.9

# pip contraints file
PROJ_PIP_CONSTRAINT ?= $(COREDIR)/heavyfs/os-$(OPENSTACK_RELEASE)-pip-upper-constraints.txt
