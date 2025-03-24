ARG DIST
ARG WEAK_DEP=0

## tier1 layer
FROM quay.io/centos/centos:stream9 AS tier1
ENV LANG=C.UTF-8
ENV HEX_VER=hex2.0
ENV GOLANG_VER=1.24.0
ENV UI_NODE_VER=22.14.0
ENV LMI_NODE_VER=12.22.12
ENV HEX_ARCH=x86_64
ENV DEVOPS_ENV=__JAIL__
ENV TZ=Asia/Taipei
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime

ARG WEAK_DEP
ARG IPT_LEGACY

#### tier1 + centos 9 repos
FROM tier1 AS tier1_centos9
ENV DIST=centos9
COPY centos9/etc/cni/net.d/87-podman.conflist /etc/cni/net.d/
RUN echo "%_netsharedpath /sys:/proc" > /etc/rpm/macros.dist
RUN dnf clean all
RUN dnf -y update
RUN rm -f /var/lib/rpm/.rpm.lock
RUN dnf install -y 'dnf-command(config-manager)'
RUN dnf config-manager --enable crb
RUN dnf install -y 'dnf-command(versionlock)'
RUN dnf install -y curl --allowerasing
RUN dnf install -y epel-release
RUN rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
RUN rpm --import https://www.elrepo.org/RPM-GPG-KEY-v2-elrepo.org
RUN dnf install -y https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm
RUN dnf config-manager --set-enabled elrepo-kernel
COPY --chmod=644 <<EOF /etc/yum.repos.d/elrepo-kernel-mirror.repo
[elrepo-kernel-mirror]
name=ELRepo Kernel Mirror
baseurl=http://mirrors.coreix.net/elrepo-archive-archive/kernel/el9/x86_64
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-elrepo.org file:///etc/pki/rpm-gpg/RPM-GPG-KEY-v2-elrepo.org
EOF
# setup dnf parallel downloads
RUN echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
RUN echo "deltarpm=0" >> /etc/dnf/dnf.conf
RUN mv /etc/redhat-release /etc/cube-release

# DDoS-ed repo sites block IPs from offending source
RUN sed -i 's/^mirrorlist=.*/#&/g' /etc/yum.repos.d/*.repo

###### tier2
FROM tier1_${DIST} AS tier2
# build essential packages
ARG HEX_BE="gcc gcc-c++ make wget ncurses-devel bash-completion dracut-tools gawk git git-lfs tree glibc-locale-source glibc-langpack-en patch rsync jq passwd"

# packages reqiured by hex sdk
# dosfstools: mkfs.vfat
# e4fsprogs: mkfs.ext4
# qemu-kvm: qemu
# qemu-img: qemu-img
# syslinux: linux bootloaders
# genisoimage: makeiso
# psmisc: pstree, killall, etc
# valgrind: memcheck
# libyaml-devel: library and header files for policy editing
# pam-devel: library for pam authentication
# readline-devel: library for cli, firsttime
# glib2-devel: the header files for the GLib library
# openssl-devel: binaries and header files
# openssh-clients: utilties for ssh
# zip/unzip: utilties for support, snapshot testing
# uuid: uuidgen for generating uuid
# vim: vim editor
# emacs: super important editor
# rrdtool: rrdtool for hex_statsd
# dos2unix: makehotfix
# util-linux-user: chsh
# rsync: rsync
ARG HEX_SDK="dosfstools e4fsprogs qemu-kvm qemu-img syslinux genisoimage psmisc valgrind libyaml-devel pam-devel readline-devel glib2-devel openssl-devel openssh-clients zip uuid vim emacs-nox rrdtool dos2unix util-linux-user nfs-utils xorriso rpmdevtools"

## packages for testing
ARG HEX_TEST="qemu-kvm-core telnet net-tools iproute iputils expect nmap-ncat dnsmasq nmap sshpass ipmitool"

# extra packages for building projects
ARG HEX_EXTRA="sudo kpartx python3-pip python3-devel java-11-openjdk maven ruby ruby-devel rpm-build rubygems squashfs-tools podman podman-docker skopeo buildah toilet linux-firmware"


RUN echo "hex" > /etc/machine-id
RUN echo "_WEAK_DEP=$WEAK_DEP" >> /etc/hex.manifest

###### install packages with WEAK_DEP == 0
FROM tier2 AS tier2_weak_dep_0
RUN dnf install -y $HEX_BE $HEX_SDK $HEX_EXTRA $HEX_TEST

###### install packages with WEAK_DEP == 1
FROM tier2 AS tier2_weak_dep_1
RUN dnf install -y --nobest --allowerasing $HEX_BE $HEX_SDK $HEX_EXTRA $HEX_TEST

######## tier3
FROM tier2_weak_dep_${WEAK_DEP} AS tier3
# kernel packages
# kernel > 5.14.0-435.el9 fails to build Nvidia driver. ERROR: modpost: GPL-incompatible module nvidia.ko uses GPL-only symbol '__rcu_read_unlock'
# ENV=KER_VER 5.14.0-435.el9
ARG KER_VER="-6.1.123-1.el9.elrepo"
ARG HEX_KERNEL="kernel-lt$KER_VER kernel-lt-core$KER_VER kernel-lt-modules$KER_VER kernel-lt-modules-extra$KER_VE kernel-lt-devel$KER_VER"
# kernel-uki-virt
RUN dnf install -y $HEX_KERNEL

# RUN [ -e /boot/hex ] || mv /boot/$(cat /etc/machine-id) /boot/hex || /bin/true
RUN [ -e /boot/hex ] || mkdir -p /boot/hex
# ubi9.tar.gz is the prerequisite of base_rootfs
COPY ubi9.tar.gz /boot/hex/ubi9.tar.gz
# RUN dnf versionlock add kernel kernel-core kernel-modules kernel-modules-extra kernel-headers kernel-uki-virt kernel-modules-core
RUN dnf versionlock add $HEX_KERNEL
RUN dnf info --installed kernel-lt > /kernel-info
RUN echo "export KER_VER=`grep Version /kernel-info | cut -d ":" -f2 | xargs`" > /cube.env
RUN echo "export KER_REL=`grep Release /kernel-info | cut -d ":" -f2 | xargs`" >> /cube.env
RUN echo "export KER_ARC=`grep Architecture /kernel-info | cut -d ":" -f2 | xargs`" >> /cube.env

# lock kernel version before updating
RUN dnf -y update

RUN . /cube.env ; mv -f /usr/lib/modules/${KER_VER}-${KER_REL}.${KER_ARC}/vmlinuz /boot/vmlinuz-${KER_VER}-${KER_REL}.${KER_ARC}

# UEFI pxe loader (this has to be installed after kernel in order to preserve proper /boot/hex folder structure)
RUN dnf install -y grub2-efi-x64 shim-x64

# install gems
RUN gem install --no-document fpm

# install diskimage-builder
RUN pip3 install --ignore-installed pip -U
RUN pip3 install --ignore-installed tox diskimage-builder

# install go and update PATH
RUN wget -qO- --no-check-certificate https://dl.google.com/go/go${GOLANG_VER}.linux-amd64.tar.gz | tar -zx  -C /usr/local/

# install nvm
# create a script file sourced by both interactive and non-interactive bash shells for installing nvm
ENV BASH_ENV /root/.bash_env
RUN touch "${BASH_ENV}"
RUN echo '. "${BASH_ENV}"' >> /root/.bashrc
# download and install nvm
RUN wget -qO- --no-check-certificate https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | PROFILE="${BASH_ENV}" bash
# install node, npm, yarn, and pnpm
RUN /bin/bash -c "nvm install $UI_NODE_VER"
RUN /bin/bash -c "nvm install $LMI_NODE_VER"
RUN /bin/bash -c "nvm use $LMI_NODE_VER && npm install -g yarn"
RUN /bin/bash -c "nvm use $UI_NODE_VER && npm install -g pnpm@latest-10"
# disable nvm to stop it from slowing down bash
RUN sed -i 's/^/#/g' $BASH_ENV
# install wheel
RUN pip3 install --ignore-installed wheel
RUN ln -sf /usr/bin/python3 /usr/bin/python

# install terraform
RUN wget https://releases.hashicorp.com/terraform/0.14.3/terraform_0.14.3_linux_amd64.zip && \
    unzip terraform_0.14.3_linux_amd64.zip -d /usr/local/bin && \
    rm -f terraform_0.14.3_linux_amd64.zip

# install helm
RUN curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# recompile iptables from src to include iptables legacy binaries
# https://qiita.com/ishida0503/items/30fffa9b4a5baa37f88f
RUN [ $IPT_LEGACY -eq 1 ] && dnf install -y yum-utils rpm-build autoconf automake bison flex libselinux-devel libpcap-devel libtool libmnl-devel libnetfilter_conntrack-devel libnfnetlink-devel libnftnl-devel || /bin/true
RUN wget https://github.com/mikefarah/yq/releases/download/v4.35.2/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq
RUN [ $IPT_LEGACY -eq 1 ] && wget https://kojihub.stream.centos.org/kojifiles/packages/iptables/1.8.8/6.el9/src/iptables-1.8.8-6.el9.src.rpm && rpm -ivh iptables-*.src.rpm || /bin/true
RUN [ $IPT_LEGACY -eq 1 ] && sed -i -re 's/(Release: [0-9]+)(%\{\?dist\}.[0-9]+)/\1_inc_legacy\2/' /root/rpmbuild/SPECS/iptables.spec || /bin/true
RUN [ $IPT_LEGACY -eq 1 ] && sed -i -e '/# drop all legacy tools/,+4d' /root/rpmbuild/SPECS/iptables.spec || /bin/true
RUN [ $IPT_LEGACY -eq 1 ] && sed -i '/^%{_libdir}\/xtables\/libxt/a %{_sbindir}/*legacy*\n%{_bindir}/iptables-xml\n%doc %{_mandir}/man1/iptables-xml*\n%doc %{_mandir}/man8/xtables-legacy*' /root/rpmbuild/SPECS/iptables.spec || /bin/true
RUN [ $IPT_LEGACY -eq 1 ] && cd /root/rpmbuild/SPECS && rpmbuild -bb iptables.spec || /bin/true
RUN [ $IPT_LEGACY -eq 1 ] && rpm -ivh --force /root/rpmbuild/RPMS/x86_64/iptables-* || /bin/true
RUN [ $IPT_LEGACY -eq 1 ] && ln -nfs xtables-legacy-multi /usr/sbin/iptables || /bin/true
RUN [ $IPT_LEGACY -eq 1 ] && ln -nfs xtables-legacy-multi /usr/sbin/iptables-restore || /bin/true
RUN [ $IPT_LEGACY -eq 1 ] && ln -nfs xtables-legacy-multi /usr/sbin/iptables-restore-translate || /bin/true
RUN [ $IPT_LEGACY -eq 1 ] && ln -nfs xtables-legacy-multi /usr/sbin/iptables-save || /bin/true
RUN [ $IPT_LEGACY -eq 1 ] && ln -nfs xtables-legacy-multi /usr/sbin/iptables-translate || /bin/true


# update env
ENV PATH="/usr/local/go/bin:${PATH}"

# update locale
RUN echo "LANG=en_US.utf-8" >> /etc/environment
RUN echo "LC_ALL=en_US.utf-8" >> /etc/environment

RUN echo "alias ls='ls --color=auto'" >> ${HOME}/.bashrc
RUN echo "stty -ixon" >> /etc/bashrc

# create manifest file
RUN echo "_HEX_ARCH=$HEX_ARCH" >> /etc/hex.manifest
RUN echo "_HEX_VER=$HEX_VER" >> /etc/hex.manifest
RUN echo "_HEX_DIST=$DIST" >> /etc/hex.manifest
RUN echo "_WEAK_DEP=$WEAK_DEP" >> /etc/hex.manifest

# generate private key for dev licence
ARG PASSPHRASE
ARG PRIVATE_PEM
ARG PUBLIC_PEM
RUN openssl genrsa -aes256 -out $PRIVATE_PEM -passout pass:$PASSPHRASE 8192
RUN openssl rsa -in $PRIVATE_PEM -outform PEM -passin pass:$PASSPHRASE -pubout -out $PUBLIC_PEM
RUN chmod 600 /etc/ssl/*.pem

######## tier4 (Jenkins specific)
FROM tier3 AS tier4
ARG JAIL_SSH="openssh-server"
ARG JAIL_VNC="openbox supervisor x11vnc xterm xorg-x11-server-Xvfb firefox which  hostname https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm"
ARG JAIL_VNC_FEH="libX11-devel libXinerama-devel imlib2-devel libcurl-devel libXt-devel"
RUN dnf -y install $JAIL_SSH $JAIL_VNC $JAIL_VNC_FEH

# jail ssh access
# Set password for the jenkins user (you may want to alter this).
RUN adduser jenkins && \
    echo "jenkins:jenkins" | chpasswd && \
    mkdir /home/jenkins/.m2 && \
    mkdir /home/jenkins/.ssh && \
    chmod 0700 /home/jenkins/.ssh

# ADD settings.xml /home/jenkins/.m2/
COPY ssh/authorized_keys /home/jenkins/.ssh/authorized_keys

RUN chown -R jenkins:jenkins /home/jenkins/.m2/ && \
    chown -R jenkins:jenkins /home/jenkins/.ssh/

RUN ssh-keygen -A
RUN (echo admin && sleep 1 && echo admin) | passwd
EXPOSE 22/tcp

RUN mkdir -p /root/.ssh
RUN chmod 0700 /root/.ssh
RUN echo "Host *" > /root/.ssh/config
RUN echo "  IdentityFile ~/.ssh/id_rsa" >> /root/.ssh/config
RUN echo "  UserKnownHostsFile /dev/null" >> /root/.ssh/config
RUN echo "  StrictHostKeyChecking no" >> /root/.ssh/config
RUN chmod 0600 /root/.ssh/config

# jail vnc access
ENV DISPLAY=:0.0 \
DISPLAY_WIDTH=1920 \
DISPLAY_HEIGHT=1080 \
TERM=xterm \
NO_VNC_HOME=/noVNC

# feh wallpaper
RUN git clone https://github.com/derf/feh.git
RUN  cd feh && make && make install

COPY vnc/*.ini /etc/supervisord.d/
ARG BLDDIR
RUN sed -i -e "s;path-to-background;$BLDDIR/cube/hex/data/hex_install/bigstack-logo.png;" /etc/supervisord.d/feh.ini
COPY supervisord.conf /etc/supervisord.conf

ENV NOVNC_VER=v1.4.0
ENV WEBSOCKIFY_VER=v0.11.0
RUN pip3 install numpy
RUN mkdir -p $NO_VNC_HOME/utils/websockify
RUN wget -qO- https://github.com/novnc/noVNC/archive/${NOVNC_VER}.tar.gz | tar xz --strip 1 -C $NO_VNC_HOME
# use older version of websockify to prevent hanging connections on offline containers, see https://github.com/ConSol/docker-headless-vnc-container/issues/50
RUN wget -qO- https://github.com/novnc/websockify/archive/${WEBSOCKIFY_VER}.tar.gz | tar xz --strip 1 -C $NO_VNC_HOME/utils/websockify
# RUN chmod +x -v $NO_VNC_HOME/utils/*.sh
# RUN ln -s /usr/bin/python2 /usr/bin/python
# create index.html to forward automatically to `vnc.html`
RUN ln -s $NO_VNC_HOME/vnc.html $NO_VNC_HOME/index.html
COPY vnc/TokenFile $NO_VNC_HOME/
COPY vnc/cube-icon.png $NO_VNC_HOME/
COPY vnc/vnc.html $NO_VNC_HOME/
COPY vnc/vnc_lite.html $NO_VNC_HOME/
COPY vnc/app/ui.js $NO_VNC_HOME/app/
COPY vnc/app/styles/base.css $NO_VNC_HOME/app/styles/

# get rid of git error msg while making builds: detected dubious ownership
COPY centos9/root/.gitconfig /root/

VOLUME /var/lib/containers/ /var/lib/rancher/

EXPOSE 6900/tcp
EXPOSE 443/tcp

WORKDIR $BLDDIR

# For running systemd
STOPSIGNAL SIGRTMIN+3
RUN systemctl mask systemd-remount-fs.service dev-hugepages.mount sys-fs-fuse-connections.mount systemd-logind.service getty.target console-getty.service systemd-udev-trigger.service systemd-udevd.service systemd-random-seed.service systemd-machine-id-commit.service
RUN dnf clean all
RUN dnf -y update
CMD ["/sbin/init"]
