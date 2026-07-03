# CUBE SDK

include ../build.mk

# Additional fakeroot build tools required by this project
# SUBDIRS += fakeroot

SUBDIRS += api
SUBDIRS += ui
SUBDIRS += cubectl
SUBDIRS += appctl
SUBDIRS += telegraf
SUBDIRS += yq
SUBDIRS += prometheus
SUBDIRS += etcd
SUBDIRS += terraform
SUBDIRS += docker
SUBDIRS += k3s
SUBDIRS += keycloak
SUBDIRS += rancher
SUBDIRS += appfw

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

SUBDIRS += fixpacks

include $(HEX_MAKEDIR)/hex_sdk.mk
