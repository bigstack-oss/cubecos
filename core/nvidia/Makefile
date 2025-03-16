# CUBE SDK

include ../../build.mk

PRIVATE_REGISTRY=localhost:5080
OS_TAG=ubuntu22.04
VERSION=1.0.0
VGPU_DRIVER_VERSION=535.129.03-grid
CUDA_VERSION=12.2.0
DRV_IMG=$(PRIVATE_REGISTRY)/driver:$(VERSION)-$(OS_TAG)

driver/${OS_TAG}/Dockerfile.orig:
	$(call RUN_CMD_TIMED, rm -rf driver && git clone https://gitlab.com/nvidia/container-images/driver,"  CLONE   nvidia container-images driver")
	$(Q)cp -f $(SRCDIR)/vgpuDriverCatalog.yaml $(SRCDIR)/NVIDIA-Linux-x86_64-$(VGPU_DRIVER_VERSION).run driver/${OS_TAG}/drivers/
	$(Q)mv driver/${OS_TAG}/Dockerfile $@

driver/${OS_TAG}/Dockerfile: driver/${OS_TAG}/Dockerfile.orig
	$(call RUN_CMD_TIMED, \
		sed $< > $@ \
		-e 's/^ARG GOLANG_VERSION.*/ENV GOLANG_VERSION=$(GOLANG_VERSION)/' \
		-e 's/^RUN OS_ARCH=.* &&/RUN /' \
		-e 's/OS_ARCH/TARGETARCH/' \
		-e 's/ TARGETARCH=.* &&//' \
		-e 's;^FROM nvidia/cuda;FROM docker.io/nvidia/cuda;' \
		,"  SED     nvidia container-images $@")

.build-img: driver/${OS_TAG}/Dockerfile
	$(call RUN_CMD_TIMED, \
		(cd driver/$(OS_TAG)/ && \
		docker build \
			--build-arg DRIVER_TYPE=vgpu \
			--build-arg DRIVER_VERSION=$(VGPU_DRIVER_VERSION) \
			--build-arg TARGETARCH=amd64 \
			--build-arg CUDA_VERSION=$(CUDA_VERSION) \
			-t $(DRV_IMG) .) \
		,"  BUILD   nvidia container-images $(DRV_IMG)")
	$(Q)touch $@

.PHONY: build-img
build-img: .build-img

.PHONY: copy-image
copy-image: .build-img
	$(call RUN_CMD_TIMED, \
		podman push $(DRV_IMG) --tls-verify=false; \
		,"  COPY    nvidia driver image $(DRV_IMG)")

clean::
	$(Q)podman image rm -f $(DRV_IMG) 2>/dev/null || true

BUILD += .build-img
BUILDCLEAN += driver .build-img

include $(HEX_MAKEDIR)/hex_sdk.mk
