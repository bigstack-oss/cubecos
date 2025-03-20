# CUBE SDK

include ../build.mk

RPMBUILD_DIR := /root/rpmbuild
GOLANG_VERSION := 1.24.0
UI_NODE_VERSION := 22.14.0
LMI_NODE_VERSION := 12.22.12

# Additional fakeroot build tools required by this project
# SUBDIRS += fakeroot

SUBDIRS += telegraf
SUBDIRS += nvidia
SUBDIRS += etcd
SUBDIRS += terraform
SUBDIRS += docker
SUBDIRS += k3s
SUBDIRS += keycloak
SUBDIRS += rancher
SUBDIRS += cubectl
SUBDIRS += appfw
SUBDIRS += api
SUBDIRS += ui
SUBDIRS += webapp

# Building heavy filesystem
SUBDIRS += heavyfs

# SDK static/shared library
LIB_SUBDIRS += cube_sdk_library
LIB_SUBDIRS += sdk_so
SUBDIRS += $(LIB_SUBDIRS)

# mysql library
SUBDIRS += mysql

SUBDIRS += modules

# Building images
SUBDIRS += main

include $(HEX_MAKEDIR)/hex_sdk.mk
