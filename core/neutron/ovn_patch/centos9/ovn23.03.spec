# Copyright (C) 2009, 2010, 2013, 2014 Nicira Networks, Inc.
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without warranty of any kind.
#
# If tests have to be skipped while building, specify the '--without check'
# option. For example:
# rpmbuild -bb --without check rhel/openvswitch-fedora.spec

# This defines the base package name's version.

%define pkgver 2.13
%define pkgname ovn23.03

# If libcap-ng isn't available and there is no need for running OVS
# as regular user, specify the '--without libcapng'
%bcond_without libcapng

# Enable PIE, bz#955181
%global _hardened_build 1

# RHEL-7 doesn't define _rundir macro yet
# Fedora 15 onwards uses /run as _rundir
%if 0%{!?_rundir:1}
%define _rundir /run
%endif

# Build python2 (that provides python) and python3 subpackages on Fedora
# Build only python3 (that provides python) subpackage on RHEL8
# Build only python subpackage on RHEL7
%if 0%{?rhel} > 7 || 0%{?fedora}
# On RHEL8 Sphinx is included in buildroot
%global external_sphinx 1
%else
# Don't use external sphinx (RHV doesn't have optional repositories enabled)
%global external_sphinx 0
%endif

# We would see rpmlinit error - E: hardcoded-library-path in '% {_prefix}/lib'.
# But there is no solution to fix this. Using {_lib} macro will solve the
# rpmlink error, but will install the files in /usr/lib64/.
# OVN pacemaker ocf script file is copied in /usr/lib/ocf/resource.d/ovn/
# and we are not sure if pacemaker looks into this path to find the
# OVN resource agent script.
%global ovnlibdir %{_prefix}/lib

Name: %{pkgname}
Summary: Open Virtual Network support
Group: System Environment/Daemons
URL: http://www.ovn.org/
Version: 23.03.0
Release: 69%{?commit0:.%{date}git%{shortcommit0}}%{?dist}
Provides: openvswitch%{pkgver}-ovn-common = %{?epoch:%{epoch}:}%{version}-%{release}
Obsoletes: openvswitch%{pkgver}-ovn-common < 2.11.0-1

# Nearly all of openvswitch is ASL 2.0.  The bugtool is LGPLv2+, and the
# lib/sflow*.[ch] files are SISSL
License: ASL 2.0 and LGPLv2+ and SISSL

# Always pull an upstream release, since this is what we rebase to.
Source: https://github.com/ovn-org/ovn/archive/v%{version}.tar.gz#/ovn-%{version}.tar.gz

%define ovscommit 8986d4d5564401eeef3dea828b51fe8bae2cc8aa
%define ovsshortcommit 8986d4d

Source10: https://github.com/openvswitch/ovs/archive/%{ovscommit}.tar.gz#/openvswitch-%{ovsshortcommit}.tar.gz
%define ovsdir ovs-%{ovscommit}

%define docutilsver 0.12
%define pygmentsver 1.4
%define sphinxver   1.1.3
Source100: https://pypi.io/packages/source/d/docutils/docutils-%{docutilsver}.tar.gz
Source101: https://pypi.io/packages/source/P/Pygments/Pygments-%{pygmentsver}.tar.gz
Source102: https://pypi.io/packages/source/S/Sphinx/Sphinx-%{sphinxver}.tar.gz

Source500: configlib.sh
Source501: gen_config_group.sh
Source502: set_config.sh

# Important: source503 is used as the actual copy file
# @TODO: this causes a warning - fix it?
Source504: arm64-armv8a-linuxapp-gcc-config
Source505: ppc_64-power8-linuxapp-gcc-config
Source506: x86_64-native-linuxapp-gcc-config

Patch:     %{pkgname}.patch

Patch900: 0001-northd-remove-dr-snat-high-priority.patch

# FIXME Sphinx is used to generate some manpages, unfortunately, on RHEL, it's
# in the -optional repository and so we can't require it directly since RHV
# doesn't have the -optional repository enabled and so TPS fails
%if %{external_sphinx}
BuildRequires: python3-sphinx
%else
# Sphinx dependencies
BuildRequires: python-devel
BuildRequires: python-setuptools
#BuildRequires: python2-docutils
BuildRequires: python-jinja2
BuildRequires: python-nose
#BuildRequires: python2-pygments
# docutils dependencies
BuildRequires: python-imaging
# pygments dependencies
BuildRequires: python-nose
%endif

BuildRequires: gcc gcc-c++ make
BuildRequires: autoconf automake libtool
BuildRequires: systemd-units openssl openssl-devel
BuildRequires: python3-devel python3-setuptools
BuildRequires: desktop-file-utils
BuildRequires: groff-base graphviz
BuildRequires: unbound-devel

# make check dependencies
BuildRequires: procps-ng
%if 0%{?rhel} == 8 || 0%{?fedora}
BuildRequires: python3-pyOpenSSL
%endif
BuildRequires: tcpdump

%if %{with libcapng}
BuildRequires: libcap-ng libcap-ng-devel
%endif

Requires: hostname openssl iproute module-init-tools

Requires(post): systemd-units
Requires(preun): systemd-units
Requires(postun): systemd-units

# to skip running checks, pass --without check
%bcond_without check

%description
OVN, the Open Virtual Network, is a system to support virtual network
abstraction.  OVN complements the existing capabilities of OVS to add
native support for virtual network abstractions, such as virtual L2 and L3
overlays and security groups.

%package central
Summary: Open Virtual Network support
License: ASL 2.0
Requires: %{pkgname}
Requires: firewalld-filesystem
Provides: openvswitch%{pkgver}-ovn-central = %{?epoch:%{epoch}:}%{version}-%{release}
Obsoletes: openvswitch%{pkgver}-ovn-central < 2.11.0-1

%description central
OVN DB servers and ovn-northd running on a central node.

%package host
Summary: Open Virtual Network support
License: ASL 2.0
Requires: %{pkgname}
Requires: firewalld-filesystem
Provides: openvswitch%{pkgver}-ovn-host = %{?epoch:%{epoch}:}%{version}-%{release}
Obsoletes: openvswitch%{pkgver}-ovn-host < 2.11.0-1

%description host
OVN controller running on each host.

%package vtep
Summary: Open Virtual Network support
License: ASL 2.0
Requires: %{pkgname}
Provides: openvswitch%{pkgver}-ovn-vtep = %{?epoch:%{epoch}:}%{version}-%{release}
Obsoletes: openvswitch%{pkgver}-ovn-vtep < 2.11.0-1

%description vtep
OVN vtep controller

%prep
%autosetup -n ovn-%{version} -a 10 -p 1

%build
%if 0%{?commit0:1}
# fix the snapshot unreleased version to be the released one.
sed -i.old -e "s/^AC_INIT(openvswitch,.*,/AC_INIT(openvswitch, %{version},/" configure.ac
%endif
./boot.sh

# OVN source code is now separate.
# Build openvswitch first.
# XXX Current openvswitch2.13 doesn't
# use "2.13.0" for version. It's a commit hash
pushd %{ovsdir}
./boot.sh
%configure \
%if %{with libcapng}
        --enable-libcapng \
%else
        --disable-libcapng \
%endif
        --enable-ssl \
        --with-pkidir=%{_sharedstatedir}/openvswitch/pki

make %{?_smp_mflags}
popd

# Build OVN.
# XXX OVS version needs to be updated when ovs2.13 is updated.
%configure \
        --with-ovs-source=$PWD/%{ovsdir} \
%if %{with libcapng}
        --enable-libcapng \
%else
        --disable-libcapng \
%endif
        --enable-ssl \
        --with-pkidir=%{_sharedstatedir}/openvswitch/pki

make %{?_smp_mflags}

%install
%make_install
install -p -D -m 0644 \
        rhel/usr_share_ovn_scripts_systemd_sysconfig.template \
        $RPM_BUILD_ROOT/%{_sysconfdir}/sysconfig/ovn

for service in ovn-controller ovn-controller-vtep ovn-northd; do
        install -p -D -m 0644 \
                        rhel/usr_lib_systemd_system_${service}.service \
                        $RPM_BUILD_ROOT%{_unitdir}/${service}.service
done

install -d -m 0755 $RPM_BUILD_ROOT/%{_sharedstatedir}/ovn

install -d $RPM_BUILD_ROOT%{ovnlibdir}/firewalld/services/
install -p -m 0644 rhel/usr_lib_firewalld_services_ovn-central-firewall-service.xml \
        $RPM_BUILD_ROOT%{ovnlibdir}/firewalld/services/ovn-central-firewall-service.xml
install -p -m 0644 rhel/usr_lib_firewalld_services_ovn-host-firewall-service.xml \
        $RPM_BUILD_ROOT%{ovnlibdir}/firewalld/services/ovn-host-firewall-service.xml

install -d -m 0755 $RPM_BUILD_ROOT%{ovnlibdir}/ocf/resource.d/ovn
ln -s %{_datadir}/ovn/scripts/ovndb-servers.ocf \
      $RPM_BUILD_ROOT%{ovnlibdir}/ocf/resource.d/ovn/ovndb-servers

install -p -D -m 0644 rhel/etc_logrotate.d_ovn \
        $RPM_BUILD_ROOT/%{_sysconfdir}/logrotate.d/ovn

# remove unneeded files.
rm -f $RPM_BUILD_ROOT%{_bindir}/ovs*
rm -f $RPM_BUILD_ROOT%{_bindir}/vtep-ctl
rm -f $RPM_BUILD_ROOT%{_sbindir}/ovs*
rm -f $RPM_BUILD_ROOT%{_mandir}/man1/ovs*
rm -f $RPM_BUILD_ROOT%{_mandir}/man5/ovs*
rm -f $RPM_BUILD_ROOT%{_mandir}/man5/vtep*
rm -f $RPM_BUILD_ROOT%{_mandir}/man7/ovs*
rm -f $RPM_BUILD_ROOT%{_mandir}/man8/ovs*
rm -f $RPM_BUILD_ROOT%{_mandir}/man8/vtep*
rm -rf $RPM_BUILD_ROOT%{_datadir}/ovn/python
rm -f $RPM_BUILD_ROOT%{_datadir}/ovn/scripts/ovs*
rm -rf $RPM_BUILD_ROOT%{_datadir}/ovn/bugtool-plugins
rm -f $RPM_BUILD_ROOT%{_libdir}/*.a
rm -f $RPM_BUILD_ROOT%{_libdir}/*.la
rm -f $RPM_BUILD_ROOT%{_libdir}/pkgconfig/*.pc
rm -f $RPM_BUILD_ROOT%{_includedir}/ovn/*
rm -f $RPM_BUILD_ROOT%{_sysconfdir}/bash_completion.d/ovs-appctl-bashcomp.bash
rm -f $RPM_BUILD_ROOT%{_sysconfdir}/bash_completion.d/ovs-vsctl-bashcomp.bash
rm -rf $RPM_BUILD_ROOT%{_sysconfdir}/logrotate.d/openvswitch
rm -f $RPM_BUILD_ROOT%{_datadir}/ovn/scripts/ovn-bugtool*
rm -f $RPM_BUILD_ROOT/%{_bindir}/ovn-docker-overlay-driver \
        $RPM_BUILD_ROOT/%{_bindir}/ovn-docker-underlay-driver

%check
%if %{with check}
    touch resolv.conf
    export OVS_RESOLV_CONF=$(pwd)/resolv.conf
    if ! make check TESTSUITEFLAGS='%{_smp_mflags}'; then
        cat tests/testsuite.log
        if ! make check TESTSUITEFLAGS='--recheck'; then
            cat tests/testsuite.log
            # Presently a test case - "2796: ovn -- ovn-controller incremental processing"
            # is failing on aarch64 arch. Let's not exit for this arch
            # until we figure out why it is failing.
            # Test case 93: ovn.at:12105       ovn -- ACLs on Port Groups is failing
            # repeatedly on s390x. This needs to be investigated.
            %ifnarch aarch64
            %ifnarch ppc64le
            %ifnarch s390x
                exit 1
            %endif
            %endif
            %endif
        fi
    fi
%endif

%clean
rm -rf $RPM_BUILD_ROOT

%pre central
if [ $1 -eq 1 ] ; then
    # Package install.
    /bin/systemctl status ovn-northd.service >/dev/null
    ovn_status=$?
    rpm -ql openvswitch-ovn-central > /dev/null
    if [[ "$?" = "0" && "$ovn_status" = "0" ]]; then
        # ovn-northd service is running which means old openvswitch-ovn-central
        # is already installed and it will be cleaned up. So start ovn-northd
        # service when posttrans central is called.
        touch %{_localstatedir}/lib/rpm-state/ovn-northd
    fi
fi

%pre host
if [ $1 -eq 1 ] ; then
    # Package install.
    /bin/systemctl status ovn-controller.service >/dev/null
    ovn_status=$?
    rpm -ql openvswitch-ovn-host > /dev/null
    if [[ "$?" = "0" && "$ovn_status" = "0" ]]; then
        # ovn-controller service is running which means old
        # openvswitch-ovn-host is installed and it will be cleaned up. So
        # start ovn-controller service when posttrans host is called.
        touch %{_localstatedir}/lib/rpm-state/ovn-controller
    fi
fi

%pre vtep
if [ $1 -eq 1 ] ; then
    # Package install.
    /bin/systemctl status ovn-controller-vtep.service >/dev/null
    ovn_status=$?
    rpm -ql openvswitch-ovn-vtep > /dev/null
    if [[ "$?" = "0" && "$ovn_status" = "0" ]]; then
        # ovn-controller-vtep service is running which means old
        # openvswitch-ovn-vtep is installed and it will be cleaned up. So
        # start ovn-controller-vtep service when posttrans host is called.
        touch %{_localstatedir}/lib/rpm-state/ovn-controller-vtep
    fi
fi

%preun central
%if 0%{?systemd_preun:1}
    %systemd_preun ovn-northd.service
%else
    if [ $1 -eq 0 ] ; then
        # Package removal, not upgrade
        /bin/systemctl --no-reload disable ovn-northd.service >/dev/null 2>&1 || :
        /bin/systemctl stop ovn-northd.service >/dev/null 2>&1 || :
    fi
%endif

%preun host
%if 0%{?systemd_preun:1}
    %systemd_preun ovn-controller.service
%else
    if [ $1 -eq 0 ] ; then
        # Package removal, not upgrade
        /bin/systemctl --no-reload disable ovn-controller.service >/dev/null 2>&1 || :
        /bin/systemctl stop ovn-controller.service >/dev/null 2>&1 || :
    fi
%endif

%preun vtep
%if 0%{?systemd_preun:1}
    %systemd_preun ovn-controller-vtep.service
%else
    if [ $1 -eq 0 ] ; then
        # Package removal, not upgrade
        /bin/systemctl --no-reload disable ovn-controller-vtep.service >/dev/null 2>&1 || :
        /bin/systemctl stop ovn-controller-vtep.service >/dev/null 2>&1 || :
    fi
%endif

%post
%if %{with libcapng}
if [ $1 -eq 1 ]; then
    sed -i 's:^#OVN_USER_ID=:OVN_USER_ID=:' %{_sysconfdir}/sysconfig/ovn
    sed -i 's:\(.*su\).*:\1 openvswitch openvswitch:' %{_sysconfdir}/logrotate.d/ovn
fi
%endif

%post central
%if 0%{?systemd_post:1}
    %systemd_post ovn-northd.service
%else
    # Package install, not upgrade
    if [ $1 -eq 1 ]; then
        /bin/systemctl daemon-reload >dev/null || :
    fi
%endif

%post host
%if 0%{?systemd_post:1}
    %systemd_post ovn-controller.service
%else
    # Package install, not upgrade
    if [ $1 -eq 1 ]; then
        /bin/systemctl daemon-reload >dev/null || :
    fi
%endif

%post vtep
%if 0%{?systemd_post:1}
    %systemd_post ovn-controller-vtep.service
%else
    # Package install, not upgrade
    if [ $1 -eq 1 ]; then
        /bin/systemctl daemon-reload >dev/null || :
    fi
%endif

%postun

%postun central
%if 0%{?systemd_postun_with_restart:1}
    %systemd_postun_with_restart ovn-northd.service
%else
    /bin/systemctl daemon-reload >/dev/null 2>&1 || :
    if [ "$1" -ge "1" ] ; then
    # Package upgrade, not uninstall
        /bin/systemctl try-restart ovn-northd.service >/dev/null 2>&1 || :
    fi
%endif

%postun host
%if 0%{?systemd_postun_with_restart:1}
    %systemd_postun_with_restart ovn-controller.service
%else
    /bin/systemctl daemon-reload >/dev/null 2>&1 || :
    if [ "$1" -ge "1" ] ; then
        # Package upgrade, not uninstall
        /bin/systemctl try-restart ovn-controller.service >/dev/null 2>&1 || :
    fi
%endif

%postun vtep
%if 0%{?systemd_postun_with_restart:1}
    %systemd_postun_with_restart ovn-controller-vtep.service
%else
    /bin/systemctl daemon-reload >/dev/null 2>&1 || :
    if [ "$1" -ge "1" ] ; then
        # Package upgrade, not uninstall
        /bin/systemctl try-restart ovn-controller-vtep.service >/dev/null 2>&1 || :
    fi
%endif

%posttrans central
if [ $1 -eq 1 ]; then
    # Package install, not upgrade
    if [ -e %{_localstatedir}/lib/rpm-state/ovn-northd ]; then
        rm %{_localstatedir}/lib/rpm-state/ovn-northd
        /bin/systemctl start ovn-northd.service >/dev/null 2>&1 || :
    fi
fi


%posttrans host
if [ $1 -eq 1 ]; then
    # Package install, not upgrade
    if [ -e %{_localstatedir}/lib/rpm-state/ovn-controller ]; then
        rm %{_localstatedir}/lib/rpm-state/ovn-controller
        /bin/systemctl start ovn-controller.service >/dev/null 2>&1 || :
    fi
fi

%posttrans vtep
if [ $1 -eq 1 ]; then
    # Package install, not upgrade
    if [ -e %{_localstatedir}/lib/rpm-state/ovn-controller-vtep ]; then
        rm %{_localstatedir}/lib/rpm-state/ovn-controller-vtep
        /bin/systemctl start ovn-controller-vtep.service >/dev/null 2>&1 || :
    fi
fi

%files
%{_bindir}/ovn-nbctl
%{_bindir}/ovn-sbctl
%{_bindir}/ovn-trace
%{_bindir}/ovn-detrace
%{_bindir}/ovn_detrace.py
%{_bindir}/ovn-appctl
%{_bindir}/ovn-ic-nbctl
%{_bindir}/ovn-ic-sbctl
%dir %{_datadir}/ovn/
%dir %{_datadir}/ovn/scripts/
%{_datadir}/ovn/scripts/ovn-ctl
%{_datadir}/ovn/scripts/ovn-lib
%{_datadir}/ovn/scripts/ovndb-servers.ocf
%{_mandir}/man8/ovn-ctl.8*
%{_mandir}/man8/ovn-appctl.8*
%{_mandir}/man8/ovn-nbctl.8*
%{_mandir}/man8/ovn-ic-nbctl.8*
%{_mandir}/man8/ovn-trace.8*
%{_mandir}/man1/ovn-detrace.1*
%{_mandir}/man7/ovn-architecture.7*
%{_mandir}/man8/ovn-sbctl.8*
%{_mandir}/man8/ovn-ic-sbctl.8*
%{_mandir}/man5/ovn-nb.5*
%{_mandir}/man5/ovn-ic-nb.5*
%{_mandir}/man5/ovn-sb.5*
%{_mandir}/man5/ovn-ic-sb.5*
%dir %{ovnlibdir}/ocf/resource.d/ovn/
%{ovnlibdir}/ocf/resource.d/ovn/ovndb-servers
%config(noreplace) %verify(not md5 size mtime) %{_sysconfdir}/logrotate.d/ovn
%config(noreplace) %verify(not md5 size mtime) %{_sysconfdir}/sysconfig/ovn

%files central
%{_bindir}/ovn-northd
%{_bindir}/ovn-ic
%{_mandir}/man8/ovn-northd.8*
%{_mandir}/man8/ovn-ic.8*
%{_datadir}/ovn/ovn-nb.ovsschema
%{_datadir}/ovn/ovn-ic-nb.ovsschema
%{_datadir}/ovn/ovn-sb.ovsschema
%{_datadir}/ovn/ovn-ic-sb.ovsschema
%{_unitdir}/ovn-northd.service
%{ovnlibdir}/firewalld/services/ovn-central-firewall-service.xml

%files host
%{_bindir}/ovn-controller
%{_mandir}/man8/ovn-controller.8*
%{_unitdir}/ovn-controller.service
%{ovnlibdir}/firewalld/services/ovn-host-firewall-service.xml

%files vtep
%{_bindir}/ovn-controller-vtep
%{_mandir}/man8/ovn-controller-vtep.8*
%{_unitdir}/ovn-controller-vtep.service

%changelog
* Fri Jun 09 2023 Igor Zhukov <ivzhukov@sbercloud.ru> - 23.03.0-69
- call ovsrcu_exit() before exit in ovn-northd and ovn-controller to make valgrind happy
[Upstream: a3aba935cda359db5d9c99e8ea9ba688e4f888bc]

* Thu Jun 08 2023 Dumitru Ceara <dceara@redhat.com> - 23.03.0-68
- controller: Turn OFTABLE_OUTPUT_INIT into an alias.
[Upstream: 8c274866a29534c6ecb80f0242798edbb078bfda]

* Thu Jun 08 2023 Ihar Hrachyshka <ihrachys@redhat.com> - 23.03.0-67
- Implement MTU Path Discovery for multichassis ports
[Upstream: 44e07200a8f04b70bbcba20d2b5346aa840b4f40]

* Thu Jun 08 2023 Ihar Hrachyshka <ihrachys@redhat.com> - 23.03.0-66
- Add new egress tables to accommodate for too-big packets handling
[Upstream: 44d6692e28478e4e971de09045f42cc5c3000540]

* Thu Jun 08 2023 Ihar Hrachyshka <ihrachys@redhat.com> - 23.03.0-65
- if-status: track interfaces for additional chassis
[Upstream: 57f15c6d78b4fbcd9ead81328e06a714b75942f0]

* Thu Jun 08 2023 Ihar Hrachyshka <ihrachys@redhat.com> - 23.03.0-64
- Track interface MTU in if-status-mgr
[Upstream: e6f097fe148deb3f60c2e2fc57e80f91986f248e]

* Thu Jun 08 2023 Ihar Hrachyshka <ihrachys@redhat.com> - 23.03.0-63
- Track ip version of tunnel in chassis_tunnel struct
[Upstream: c8fccfa720b7d8e176be05bfd37fd6e74764ee3d]

* Thu Jun 08 2023 Ales Musil <amusil@redhat.com> - 23.03.0-62
- northd: Add logical flow to skip GARP with LLA (#2211240)
[Upstream: dc0b0b55d93cb2516f1759b65f198485597d4575]

* Thu Jun 08 2023 Vladislav Odintsov <odivlad@gmail.com> - 23.03.0-61
- northd: match only on supported protocols to handle_svc_check (#1913162)
[Upstream: 822861db016d9360d6a88a486d5db8d5936e66fa]

* Thu Jun 08 2023 Xavier Simonart <xsimonar@redhat.com> - 23.03.0-60
- tests: Fixed "nested containers" test
[Upstream: f914cf2cab4b4a872d246961c6521cd8a48f2bd3]

* Thu Jun 08 2023 Xavier Simonart <xsimonar@redhat.com> - 23.03.0-59
- tests: fix flaky Multiple OVS interfaces bound to same logical ports
[Upstream: 8f29930c22687c3247a784e1e2fe4a6dc0fdd86c]

* Thu Jun 08 2023 Ales Musil <amusil@redhat.com> - 23.03.0-58
- system-tests: Prevent flakiness in ovn mirroring
[Upstream: 352041d0fa66772d86980f46c63e023c40286723]

* Thu Jun 08 2023 Ales Musil <amusil@redhat.com> - 23.03.0-57
- northd: Fix address set incremental processing (#2196885)
[Upstream: e8baef1c0fc671fe4e2d3af63de979e22a0c899d]

* Tue May 30 2023 Brian Haley <haleyb.dev@gmail.com> - 23.03.0-56
- controller: Ignore DNS queries with RRs
[Upstream: 529ea698f5d1d2b7083210318cfc0a64b701ca62]

* Tue May 30 2023 Ales Musil <amusil@redhat.com> - 23.03.0-55
- ci: ovn-kubernetes: Align the timeouts with u/s ovnk
[Upstream: ecc0a06af3bb47fe49ee897896af35a0efe33486]

* Tue May 30 2023 Dumitru Ceara <dceara@redhat.com> - 23.03.0-54
- controller: Handle OpenFlow errors. (#2134880)
[Upstream: 158463b94f5b6c37a37d9755ba9d5ef7473d35d3]

* Tue May 30 2023 Vladislav Odintsov <odivlad@gmail.com> - 23.03.0-53
- controller: fix typo in comments
[Upstream: f24e9bf7b4b5822e0d37a4382fe49607c132a3ee]

* Tue May 30 2023 Vladislav Odintsov <odivlad@gmail.com> - 23.03.0-52
- northd: build vtep hairpin lflows only for lswitches with vtep lports
[Upstream: 222f74acea04c9ae46bb3767ff256f8249ee7ab8]

* Tue May 30 2023 Vladislav Odintsov <odivlad@gmail.com> - 23.03.0-51
- northd: fix ls_in_hairpin l3dgw flow generation
[Upstream: e4f8547be8774c085ef212fbed3e5e76e77d661c]

* Fri May 26 2023 Han Zhou <hzhou@ovn.org> - 23.03.0-50
- ovn-controller.c: Fix assertion failure during address set update.
[Upstream: 777786f38a61041898891ccbb3f139b0552e5794]

* Fri May 19 2023 Mark Michelson <mmichels@redhat.com> - 23.03.0-49
- Pass localnet traffic through CT when a LB is configured. (#2164652)
[Upstream: 2449608303464d62ff5b1a89e20e476248d1e82b]

* Fri May 19 2023 Mark Michelson <mmichels@redhat.com> - 23.03.0-48
- tests: Use stricter IP match for FORMAT_CT.
[Upstream: a1d8ebd306021844646629c42bd638203399c568]

* Wed May 17 2023 Ales Musil <amusil@redhat.com> - 23.03.0-47
- tests: Fix flakiness of policy based routing on slower systems
[Upstream: bb22fe9c4591dc96d98bf2c2c3f629efb5721757]

* Wed May 17 2023 Vladislav Odintsov <odivlad@gmail.com> - 23.03.0-46
- ovn-controller docs: fix typo in ovn-monitor-all description
[Upstream: 0ba1609d6426cd779f48cb5a97e63c0a7811dc03]

* Wed May 10 2023 Ales Musil <amusil@redhat.com> - 23.03.0-45
- system-tests: Replace use of ADD_INT with ADD_VETH
[Upstream: c2f36b530613728100b1dbdf7f967c4a87053155]

* Wed May 10 2023 Lorenzo Bianconi <lorenzo.bianconi@redhat.com> - 23.03.0-44
- controller: fix possible unaligned accesses in DHCPv6 code
[Upstream: 080cbcd95d3d065524272f5f1d0bed11df35a9d4]

* Tue May 09 2023 Lorenzo Bianconi <lorenzo.bianconi@redhat.com> - 23.03.0-43
- mirror: fix ovn mirror support with IPv6 (#2168119)
[Upstream: 5255303229f4da0c1478656597c774510ceda4e9]

* Mon May 08 2023 Xavier Simonart <xsimonar@redhat.com> - 23.03.0-42
- ovn-controller: fixed port not always set down when unbinding interface (#2150905)
[Upstream: 39930c0254bc8758b5722e0f2c3a7fdc43256888]

* Mon May 08 2023 Xavier Simonart <xsimonar@redhat.com> - 23.03.0-41
- ovn-controller: fixed ovn-installed not always properly added or removed.
[Upstream: 395eac485b871ef75bb0b5f29b09ebd1cb877ca8]

* Mon May 08 2023 Wei Li <liw@yusur.tech> - 23.03.0-40
- documentation: packets that arrive from other chassis resubmit to table 38
[Upstream: 4ad402df2870c44234945b462345bfcb0c95b6f6]

* Mon May 08 2023 Tao Liu <taoliu828@163.com> - 23.03.0-39
- northd: fix use-after-free after lrp destroyed
[Upstream: fd0111e59c6a78acf70dd47e10e724210c2e94ea]

* Mon May 08 2023 Ihar Hrachyshka <ihrachys@redhat.com> - 23.03.0-38
- docs: document that vxlan is supported for encap type
[Upstream: 31bc347255a9206b29dc3f9af14c8af75ea9600e]

* Mon May 08 2023 Xavier Simonart <xsimonar@redhat.com> - 23.03.0-37
- tests: Fixed flaky lr multiple gw ports
[Upstream: 94dea8bb6bba439de673fa4fa72e3fa3f8c44593]

* Mon May 08 2023 Xavier Simonart <xsimonar@redhat.com> - 23.03.0-36
- Fix test "load-balancing"
[Upstream: bfdfb9a0565b2f21f59120b360db1aa59b24f96d]

* Fri May 05 2023 Dumitru Ceara <dceara@redhat.com> - 23.03.0-35
- tests: Retry inject-pkt in case ovn-controller is still busy.
[Upstream: d6cad0cc05f752a83f72c82881a76642301125b9]

* Tue May 02 2023 wangchuanlei <wangchuanlei@inspur.com> - 23.03.0-34
- pinctrl: fix restart of controller when bfd min_tx is too low.
[Upstream: 77d0ff0dace95ce6c8453c2b95f65d18892133b6]

* Tue May 02 2023 Ales Musil <amusil@redhat.com> - 23.03.0-33
- ovn-nbctl: Fix unhandled NULL return from normalize_prefix_str
[Upstream: 86ceec393a9b776990bb24625bf9ca13ce9dfe05]

* Mon May 01 2023 Xavier Simonart <xsimonar@redhat.com> - 23.03.0-32
- tests: decrease risk of flaky failures of ovn -- CoPP system test
[Upstream: b81229835436b63a593e0e6a55bb639309101592]

* Mon May 01 2023 Xavier Simonart <xsimonar@redhat.com> - 23.03.0-31
- tests: check arguments count of OVS_WAIT_UNTIL
[Upstream: 352c584c403ce914b59e3c3c95028949ec3ede05]

* Mon May 01 2023 Xavier Simonart <xsimonar@redhat.com> - 23.03.0-30
- tests: Fixed wrong usage of OVS_WAIT_UNTIL
[Upstream: b88d8bbba3ba59ee0a3c2d3fb62cab748e1b59dc]

* Mon May 01 2023 Xavier Simonart <xsimonar@redhat.com> - 23.03.0-29
- tests: Fixed "1 LR with HA distributed router gateway port"
[Upstream: 1758332a51766231e74479302ee8efdfc07bf33c]

* Fri Apr 21 2023 Mark Michelson <mmichels@redhat.com> - 23.03.0-28
- tests: Skip "daemon ssl files change" when SSL is disabled.
[Upstream: 3d231640d852bc4c7b49d17de80ba747bebe8817]

* Wed Apr 19 2023 Ihar Hrachyshka <ihrachys@redhat.com> - 23.03.0-27
- Omit ACLs for nd || nd_ra || nd_rs || mldv1 || mldv2 (#2149731)
[Upstream: 6e6cc27bdb9735a6461b53771b3969a2ca230cab]

* Wed Apr 19 2023 Ihar Hrachyshka <ihrachys@redhat.com> - 23.03.0-26
- tests: define fmt_pkt function to construct packets with scapy
[Upstream: b797e5dbd955ee61d503bb38dade490957bce563]

* Wed Apr 19 2023 Ales Musil <amusil@redhat.com> - 23.03.0-25
- controller: Prevent race in tunnel cleanup
[Upstream: 40befbb1d508db48f894cb190637ee33cccf0977]

* Thu Apr 13 2023 Han Zhou <hzhou@ovn.org> - 23.03.0-24
- northd.c: Avoid sending ICMP time exceeded for multicast packets.
[Upstream: a38a5df4a49ddf678d6a50de39b613b8f0305e26]

* Thu Apr 13 2023 Han Zhou <hzhou@ovn.org> - 23.03.0-23
- northd.c: TTL discard flow should support for both ipv4 and ipv6.
[Upstream: d42d070bd2598b72c13d2a67209d368acc8128b8]

* Tue Apr 11 2023 Ales Musil <amusil@redhat.com> - 23.03.0-22
- northd: Update the is_stateless helper for router nat
[Upstream: 99b42566998c9e9b952cdfe3f8435e8bd79eca43]

* Tue Apr 11 2023 Eelco Chaudron <echaudro@redhat.com> - 23.03.0-21
- ci: Add arping package to run floating IP tests.
[Upstream: 825164cd4164e9c9bf5c66ebe00e147f1e2ac1fd]

* Tue Apr 11 2023 Ales Musil <amusil@redhat.com> - 23.03.0-20
- controller: Clear tunnels from old integration bridge (#2173635)
[Upstream: 8481abcc04fee5e0ecd881e599be178625ad1522]

* Tue Apr 11 2023 Lorenzo Bianconi <lorenzo.bianconi@redhat.com> - 23.03.0-19
- northd: revert ct.inv drop flows
[Upstream: 04d7552479736bd2da84dd5d2be146fa4a51e3e6]

* Thu Apr 06 2023 Lorenzo Bianconi <lorenzo.bianconi@redhat.com> - 23.03.0-18
- northd: take into account qos_min_rate in port_has_qos_params
[Upstream: 0bbcfb52f0248d839e413acaf2b116bb7b1c4db6]

* Thu Mar 30 2023 Ales Musil <amusil@redhat.com> - 23.03.0-17
- system-tests: Reduce flakiness of netcat UDP clients
[Upstream: 6c2d80c5bb6a2cd7c353b796a7d46b3962a06c9f]

* Tue Mar 28 2023 Dumitru Ceara <dceara@redhat.com> - 23.03.0-16
- Revert "DOWNSTREAM: Forcefully disable backend conntrack flushing."
[Upstream: 8c98303437610a32faff8c0e7d8eff419b40619e]

* Tue Mar 28 2023 Xavier Simonart <xsimonar@redhat.com> - 23.03.0-15
- northd: prevents sending packet to conntrack for router ports (#2062431)
[Upstream: 2bab96e899b5da5ae0c3b24bd04ece93d1339824]

* Tue Mar 28 2023 Dumitru Ceara <dceara@redhat.com> - 23.03.0-14
- lb: Allow IPv6 template LBs to use explicit backends.
[Upstream: d01fdfdb2c97222cf326c8ab5579f670ded6e3cb]

* Tue Mar 28 2023 Lorenzo Bianconi <lorenzo.bianconi@redhat.com> - 23.03.0-13
- controller: lflow: do not use tcp as default IP protocol for ct_snat_to_vip action (#2157846)
[Upstream: 6a16c741e5a10a817ca8251898f48bf9eeb971f5]

* Tue Mar 28 2023 Ales Musil <amusil@redhat.com> - 23.03.0-12
- northd: Drop packets for LBs with no backends (#2177173)
[Upstream: 77384b7fe3f7d3260fd2f94a3bd75b8ca79f56ae]

* Mon Mar 27 2023 Ales Musil <amusil@redhat.com> - 23.03.0-11
- northd: Use generic ct.est flows for LR LBs (#2172048 2170885)
[Upstream: 81eaa98bbb608bda320abfa0122ba073de6597d7]

* Thu Mar 23 2023 Lorenzo Bianconi <lorenzo.bianconi@redhat.com> - 23.03.0-10
- northd: drop ct.inv packets in post snat and lb_aff_learn stages (#2160685)
[Upstream: 0af110c400cc29bb037172cdfd674794716771df]

* Mon Mar 20 2023 Ales Musil <amusil@redhat.com> - 23.03.0-9
- controller: Add config option per LB to enable/disable CT flush (#2178962)
[Upstream: 89fc85fa7f2b00f404ec5aef4ce8f2236474fbab]

* Thu Mar 16 2023 Dumitru Ceara <dceara@redhat.com> - 23.03.0-8
- DOWNSTREAM: Forcefully disable backend conntrack flushing. (#2178962)
[Upstream: b7522be8bf28534cc422234e8d9484b9ef4220d9]

* Thu Mar 16 2023 Dumitru Ceara <dceara@redhat.com> - 23.03.0-7
- northd: Ignore remote chassis when computing the supported feature set.
[Upstream: 80b7e48a877abd337eb54b9bb9c7b4280aa9ff74]

* Wed Mar 08 2023 Ilya Maximets <i.maximets@ovn.org> - 23.03.0-6
- controller: Use ofctrl_add_flow for CT SNAT hairpin flows.
[Upstream: 888215e2164b476462f12d206a3d734958ef79e2]

* Wed Mar 08 2023 Vladislav Odintsov <odivlad@gmail.com> - 23.03.0-5
- rhel: pass options to stop daemon command in systemd units
[Upstream: ed7095613abf3d36cbcf347e1238b84e6843eaf1]

* Fri Mar 03 2023 Mark Michelson <mmichels@redhat.com> - 23.03.0-4
- Prepare for 23.03.1.
[Upstream: e98ea52f12de2a7d6a9a7547b6b0a493a78f0fed]

