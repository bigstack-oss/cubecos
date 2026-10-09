# Tempest runner for CubeCOS: pinned Tempest + plugins, Octavia test server and Cirros baked in (offline runs)
FROM registry.access.redhat.com/ubi9/ubi:latest AS build
RUN dnf -y -q install golang gcc python3.11 python3.11-devel python3.11-pip patch && dnf clean all
ARG TEMPEST_PIP
COPY constraints.txt /src/
COPY patches/ /src/patches/
RUN python3.11 -m venv /opt/tempest/venv \
 && /opt/tempest/venv/bin/pip install -q --upgrade pip \
 && /opt/tempest/venv/bin/pip install -q -c /src/constraints.txt $TEMPEST_PIP \
      python-openstackclient python-octaviaclient python-manilaclient python-designateclient python-watcherclient \
      python-subunit junitxml os-testr \
 && /opt/tempest/venv/bin/pip check
# manila: DHCP test subnets, wait for share-server ports; tempest: retry SubnetInUse on credential teardown
RUN cd /opt/tempest/venv/lib/python3.11/site-packages \
 && for p in /src/patches/*.patch; do patch -p0 --forward < $p || exit 1; done
RUN cd /opt/tempest/venv/lib/python3.11/site-packages/octavia_tempest_plugin/contrib/test_server \
 && CGO_ENABLED=0 GO111MODULE=off go build -a -ldflags '-s -w -extldflags "-static"' -o /opt/tempest/test_server.bin test_server.go
ARG CIRROS_VER=0.6.2
ARG CIRROS_SHA256=07e44a73e54c94d988028515403c1ed762055e01b83a767edf3c2b387f78ce00
RUN curl -sfL -o /opt/tempest/cirros.img https://github.com/cirros-dev/cirros/releases/download/${CIRROS_VER}/cirros-${CIRROS_VER}-x86_64-disk.img \
 && echo "${CIRROS_SHA256}  /opt/tempest/cirros.img" | sha256sum -c -

FROM registry.access.redhat.com/ubi9/ubi:latest
ARG OPENSTACK_RELEASE
ARG TEMPEST_VER
LABEL cube.openstack-release=$OPENSTACK_RELEASE cube.tempest-version=$TEMPEST_VER
RUN dnf -y -q install python3.11 && dnf clean all
COPY --from=build /opt/tempest /opt/tempest
COPY tempest.conf.in exclude-cos.txt preflight.py render-conf.sh run.sh teardown.sh /opt/tempest/
ENV PATH=/opt/tempest/venv/bin:$PATH
WORKDIR /work
ENTRYPOINT ["/opt/tempest/run.sh"]
