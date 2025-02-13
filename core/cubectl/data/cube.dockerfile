FROM registry.access.redhat.com/ubi8/ubi-init:latest

RUN rm -f /etc/yum.repos.d/* /etc/pki/rpm-gpg/* /etc/pki/entitlement/*
RUN rpm -e --allmatches gpg-pubkey

COPY centos8/*.repo /etc/yum.repos.d/
COPY centos8/RPM-GPG-KEY-* /etc/pki/rpm-gpg/

RUN dnf -y update && dnf -y install openssh-server rsync hostname iproute net-tools
RUN sed -i '/^PermitRootLogin/c\PermitRootLogin yes' /etc/ssh/sshd_config
RUN echo 'root:admin' | chpasswd

COPY etcd.service etcd-watch.service /lib/systemd/system/
