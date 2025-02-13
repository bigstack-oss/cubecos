#!/usr/bin/env bash

function cleanup()
{
    buildah rm $ctr || true
}
trap cleanup EXIT ERR

set -o errexit

ctr=$(buildah from registry.access.redhat.com/ubi9/ubi-init:latest)

buildah run $ctr rm -f \
    /etc/yum.repos.d/ubi.repo \
    /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-beta \
    /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release \
    /etc/pki/entitlement/*
buildah run $ctr rpm -e --allmatches gpg-pubkey
buildah copy $ctr $TOP_SRCDIR/jail/centos8/*.repo /etc/yum.repos.d/
buildah copy $ctr $TOP_SRCDIR/jail/centos8/RPM-GPG-KEY-* /etc/pki/rpm-gpg/

buildah run $ctr dnf update -y
buildah run $ctr dnf install -y sudo hostname rsync iproute net-tools openssl jq less

# sshd
buildah run $ctr dnf install -y openssh-clients openssh-server
buildah run $ctr sed -i '/^PermitRootLogin/c\PermitRootLogin yes' /etc/ssh/sshd_config
buildah run $ctr sh -c 'echo "root:admin" | chpasswd'

buildah copy $ctr $TOP_SRCDIR/core/cubectl/data/etcd.service $TOP_SRCDIR/core/cubectl/data/etcd-watch.service /lib/systemd/system/

# docker
buildah run $ctr dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
buildah run $ctr dnf install -y docker-ce kernel-core kmod

buildah config --volume=/var/lib/docker --volume=/var/lib/rancher $ctr

buildah commit $ctr cube:latest
