# Version pins for the homebrew components (cubecos#2067).
#
# <NAME>_REF  git branch or tag a non-RC build clones and builds from source.
# <NAME>_RPM  prebuilt RPM an RC build (RC=...) downloads instead: "<tag>/<asset>" under the
#             repo's GitHub Releases, fetched via $(GITHUB_DL_BASE) and checked against
#             <NAME>_RPM_SHA256. Left empty, an RC build builds from <NAME>_REF too.
#
# A release branch pins every _REF to a tag and every _RPM to that tag's asset.
# Override per build with `make <NAME>_REF=<ref>` or `make RC=... <NAME>_RPM=... <NAME>_RPM_SHA256=...`.
CUBE_COS_API_REF          ?= develop
CUBE_COS_API_RPM          ?= v3.2.0-rc1/cube-cos-api-v3.1.0-1.fc35.575bb9b.x86_64.rpm
CUBE_COS_API_RPM_SHA256   ?= 0a461d6dc21a5cf6510f1013556ad187ef4b0410894e1364e9e97a2843467f80

CUBE_COS_APPFW_REF        ?= develop
CUBE_COS_APPFW_RPM        ?= v3.2.0-rc1/cube-cos-app-framework-v3.1.0-1.fc35.0a7d73d.x86_64.rpm
CUBE_COS_APPFW_RPM_SHA256 ?= 697210f88e9b5a7f4dc1f624a118330e4ce15f06230b8b469e1874cf6e34844a

CUBE_COS_UI_REF           ?= develop
CUBE_COS_UI_RPM           ?= cube-cos-ui-v3.2.0-rc1/cube-cos-ui-3.1.0-1.45fc649.x86_64.rpm
CUBE_COS_UI_RPM_SHA256    ?= 0d93b775dbd0bd489351dbaf62abdc71ec9a51697f29d78286cac9a10c8271cc

CUBE_COS_LOGIN_REF        ?= develop
CUBE_COS_LOGIN_RPM        ?= cube-cos-login-v3.2.0-rc1/cube-cos-login-26.0.0-1.45fc649.x86_64.rpm
CUBE_COS_LOGIN_RPM_SHA256 ?= f66619bf1f00b23c2f8759e91799fa02102ba091e6017974c1174b29f89b81ea

# lachesis has no release rpm yet, so RC builds also build it from _REF until one is pinned
LACHESIS_REF              ?= develop
LACHESIS_RPM              ?=
LACHESIS_RPM_SHA256       ?=

# no prebuilt rpm: skyline-console is a wheel built into the rootfs; cube-cos-driver ships
# binaries, not an rpm. RC and non-RC builds both build these from _REF.
SKYLINE_CONSOLE_REF       ?= master
CUBE_COS_DRIVER_REF       ?= develop
