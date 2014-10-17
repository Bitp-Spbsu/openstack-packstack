%global with_doc %{!?_without_doc:1}%{?_without_doc:0}
%global git_revno 1238


# openstack-packstack ----------------------------------------------------------

Name:           openstack-packstack
Version:        2014.1.1
Release:        0.28.dev%{git_revno}%{?dist}
Summary:        Openstack Install Utility

Group:          Applications/System
License:        ASL 2.0 and GPLv2
URL:            https://github.com/stackforge/packstack
# Tarball is created by bin/release.sh
Source0:        http://mmagr.fedorapeople.org/downloads/packstack/packstack-%{version}dev%{git_revno}.tar.gz

Patch0:         enable-epel.patch
Patch1:         ceph-backend.patch

BuildArch:      noarch

BuildRequires:  python2-devel
BuildRequires:  python-setuptools

Requires:       openssh-clients
Requires:       python-netaddr
Requires:       openstack-packstack-puppet == %{version}-%{release}
Requires:       openstack-puppet-modules

%description
Packstack is a utility that uses Puppet modules to install OpenStack. Packstack
can be used to deploy various parts of OpenStack on multiple pre installed
servers over ssh.


# openstack-packstack-puppet ---------------------------------------------------

%package puppet
Summary:        Packstack Puppet module
Group:          Development/Libraries

%description puppet
Puppet module used by Packstack to install OpenStack


# openstack-packstack-doc ------------------------------------------------------

%if 0%{?with_doc}
%package doc
Summary:          Documentation for Packstack
Group:            Documentation

%if 0%{?rhel} == 6
BuildRequires:  python-sphinx10
%else
BuildRequires:  python-sphinx
%endif

%description doc
This package contains documentation files for Packstack.
%endif


# prep -------------------------------------------------------------------------

%prep
%setup -n packstack-%{version}dev%{git_revno}
%patch0 -p1
%patch1 -p1

# Sanitizing a lot of the files in the puppet modules
find packstack/puppet/modules \( -name .fixtures.yml -o -name .gemfile -o -name ".travis.yml" -o -name .rspec \) -exec rm {} +
find packstack/puppet/modules \( -name "*.py" -o -name "*.rb" -o -name "*.pl" \) -exec sed -i '/^#!/{d;q}' {} + -exec chmod -x {} +
find packstack/puppet/modules \( -name "*.sh" \) -exec sed -i 's/^#!.*/#!\/bin\/bash/g' {} + -exec chmod +x {} +
find packstack/puppet/modules -name site.pp -size 0 -exec rm {} +
find packstack/puppet/modules \( -name spec -o -name ext \) | xargs rm -rf

# Moving this data directory out temporarily as it causes setup.py to throw errors
rm -rf %{_builddir}/puppet
mv packstack/puppet %{_builddir}/puppet


# build ------------------------------------------------------------------------

%build
%{__python} setup.py build

%if 0%{?with_doc}
cd docs
%if 0%{?rhel} == 6
make man SPHINXBUILD=sphinx-1.0-build
%else
make man
%endif
%endif


# install ----------------------------------------------------------------------

%install
%{__python} setup.py install --skip-build --root %{buildroot}

# Delete tests
rm -fr %{buildroot}%{python_sitelib}/tests

# Install Puppet module
mkdir -p %{buildroot}/%{_datadir}/openstack-puppet/modules
cp -r %{_builddir}/puppet/modules/packstack  %{buildroot}/%{_datadir}/openstack-puppet/modules/
cp -r %{_builddir}/puppet/modules/remote  %{buildroot}/%{_datadir}/openstack-puppet/modules/

# Move Puppet manifest templates back to original place
mkdir -p %{buildroot}/%{python_sitelib}/packstack/puppet
mv %{_builddir}/puppet/templates %{buildroot}/%{python_sitelib}/packstack/puppet/

%if 0%{?with_doc}
mkdir -p %{buildroot}%{_mandir}/man1
install -p -D -m 644 docs/_build/man/*.1 %{buildroot}%{_mandir}/man1/
%endif


# files ------------------------------------------------------------------------

%files
%doc LICENSE
%{_bindir}/packstack
%{python_sitelib}/packstack
%{python_sitelib}/packstack-%{version}*.egg-info

%files puppet
%defattr(644,root,root,755)
%{_datadir}/openstack-puppet/modules/packstack
%{_datadir}/openstack-puppet/modules/remote

%if 0%{?with_doc}
%files doc
%{_mandir}/man1/packstack.1.gz
%endif


# changelog --------------------------------------------------------------------

%changelog
* Mon Aug 18 2014  Iván Chavero <ichavero@redhat.com> - 2014.1.1-0.28.dev1238
- Fixed installation of puppet-remote module (rhbz#1128212)

* Fri Aug 15 2014  Iván Chavero <ichavero@redhat.com> - 2014.1.1-0.27.dev1238
- [Nova] Added FW rules for live migration (rhbz#1117524)
- [Nova] Add live migration support and firewall rules (rhbz#1122457, rhbz#1122703, rhbz#1117524)
- [Horizon] Remove ServerAlias definitions (rhbz#1119920)
- [Mysql] Fixed remote DB installations (rhbz#1128212)
- [Packstack] Ensures RHOS SOS Plugins is installed on all nodes (rhbz#1053734)
- [Packstack] Reload sysctl (rhbz#1104619)
- [Packstack] Adds Warning when NetworkManager is active on hosts (rhbz#1117115)
- [Amqp] Adds Scientific Linux 7 Support.
- [Nova] Enable migration support in libvirt
- [Heat] Configures Heat to use Trusts by default
- [Packstack] Adds Better rst Output when using 'packstack -o'
- [Heat] Adds Undocumented HEAT Options

* Tue Jul 15 2014  Iván Chavero <ichavero@redhat.com> - 2014.1.1-0.26.dev1220
- [Neutron] Don't use ML2 parameters for other plugins (rhbz#1119473)
- [Neutron] Fixes Duplicated variables in neutron manifests
- [Tempest] Fixes incomplete Tempest question in interactive mode (rhbz#1116431)
- [Packstack] Fixes Facts string comparisons in CentOS 7 (rhbz#1117035)
- [Neutron] Sets l2population to true on nodes that populate l2 agents (rhbz#1118010)
- [Ceilometer] Ensure ceilometer depends on nova-common package
- Remove rhel7-qpid-018.patch becaue it does not apply anymore
- Add 0001-Make-amqp.pp-compatible-with-RHOS-version-of-qpidd.patch as substitute of
  rhel7-qpid-018.patch
- [Ceilometer] Ensure ceilometer depends on nova common package (rhbz#1115946)
- [Nova] Fixes libvirtd restart (rhbz#1109362)

* Wed Jul 02 2014  Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.25.dev1208
- [Nova] Change nova api steps generating puppet manifests to fix neutron (rhbz#1115458)
- [Provision] Make sure bridge provision is disabled for Nova network (rhbz#1115444)
- [Nova] Restart libvirt only when deploying nova network on compute (rhbz#1114930)
- [Packstack] Compare CONFIG_PROVISION_ALL_IN_ONE_OVS_BRIDGE to 'false' (rhbz#1115163)
- [Packstack] Stop firewalld before service iptables and not class firewall (rhbz#1114121)
- [Packstack] Prevents packstack to create user/tenant called undef (rhbz#1114590)
- [Neutron] Fixed lbaas to be installed on network nodes (rhbz#1114261)

* Mon Jun 30 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.24.dev1196
- [Swift] Change Swift proxy pipeline quota entries to use underscore instead of dash (rhbz#1114262)

* Wed Jun 25 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.23.dev1194
- [Neutron] Fixes DHCP firewall protocol (rhbz#1112019)
- [Neutron] Setup neutron l2 plugin configs only on neutron api nodes (rhbz#1113472)
- [Neutron] Connect bridge with interface only on network hosts (rhbz#1072268)
- [Neutron] Enables Debugging Mode for Neutron Agents (rhbz#1090785)
- [Swift] Add crossdomain middleware into switf proxy pipeline

* Tue Jun 24 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.22.dev1184
- [Heat] Add CONFIG_CONTROLLER_HOST to heat cfn config (rhbz#1054353)
- [MySQL] Fix check for CentOS in mysql_install (rhbz#1111318)
- [Packstack] prevent packstack from aborting of o-p-m package has no deps (lp#1332705)
- [Packstack] configure authorized_keys locally for --allinone (rhbz#1111705)
- [Packstack] Fixed subscription-manager registration (rhbz#1093482)
- [Neutron] Connect bridge with interface also for GRE and VXLAN (rhbz#1072268)
- [Neutron] Fixed metering to be installed on each L3 agent (rhbz#1108499)
- [Neutron] Don't install l2 agent on api node by default (rhbz#1076888)
- [Tempest] Provision Demo/Tempest Separation (rhbz#1111969)

* Wed Jun 18 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.21.dev1157
- [Horizon] Fixes horizon error when neutron disabled (rhbz#1110492)
- [Nova] Fix libvirt livemigration (rhbz#1100356)
- [SeLinux] Start auditd by default (rhbz#1109250)
- [Provision] Provision also on multinode setup (rhbz#1100356)

* Tue Jun 17 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.20.dev1149
- [Cinder] Moved cinder::volume::iscsi out of main template (rhbz#1106512)
- [Neutron] Only setup nova notifications if nova is being installed
- [Heat] Set EC2 auth url for Heat (rhbz#1106394)
- [Neutron] Handle interface names containing ".", "-" or ":" (rhbz#1105166, rhbz#1057938)
- [Packstack] Use openstack-selinux on RHEL-7 (rhbz#1109308)
- [Cinder] Add forgotten cinder backend vmdk (rhbz#1109374)
- [Nova] Restart libvirtd after Nova Network install (rhbz#1109362)
- [Firewall] Make sure firewalld is down before iptables starts
- Removed 0001-Use-openstack-selinux-on-RHEL-7.patch and el7-swift.patch

* Wed Jun 11 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.19.dev1129
- [Packstack] Add special backward compat layer for Swift plugin
- [Horizon] Added neutron options for Horizon (rhbz#1103148)
- [MySQL] Make innodb tweaking compatible with mysql (rhbz#1023221)
- [Packstack] Synced packstack.rst
- [Swift] Make sure swift cactch_errors middleware is first in pipeline (rhbz#1023221)
- [Neutron] Don't use vs_bridge with provider network (rhbz#1105884)
- [Neutron] Fix firewall rules with multiple network hosts (rhbz#1105248)
- [Horizon] Refactor horizon ssl setup to use puppet-horizon (rhbz#1104226)
- [Neutron] Open VXLAN udp port (rhbz#1100993)
- [Heat] Add Keystone domain for Heat support (rhbz#1076172)
- [Neutron] Added Neutron FWaaS (rhbz#1098765)
- [Nagios] updating nagios checks for cinder and glance to list all items not just the admins

* Wed Jun 04 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.16.dev1109
- [Packstack] Fixes language parsing problems
- [Neutron] Fixed firewall protocols (rhbz#1100993)
- [Nagios] Fix {nagios,monitoring}-plugins-ping confusion (rhbz#1100037, rhbz#1096154, rhbz#1101665, rhbz#1103695)

* Mon Jun 02 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.15.dev1102
- [Neutron] Opens GRE and VXLAN port (rhbz#1100993)
- [Packstack] Fixed Heat plugin (rhbz#1103382)

* Fri May 30 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.14.dev1100
- [Packstack] Parameter deprecation support
- [Firewall] firewalld workaround (rhbz#1099840)
- [Ceilometer] Install Ceilometer notification agent (rhbz#1096268)
- [Nova] Fallback for qemu-kvm
- [Neutron] Switch default Neutron l2 plugin to ml2 and switch segregation type to vxlan
- Removed 0001-Workaround-for-stoped-openstack-ceilometer-notificat.patch

* Wed May 14 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.13.dev1085
- [Packstack] Add infos about ML2 params in the packstack man page (rhbz#1065979)
- [MySQL] Add performance configuration for InnoDB (rhbz#1078999)
- [Nova] Force qemu-kvm-rhev on RHELs (rhbz#1049861)
- [Packstack] Plugins refactor (lp#simplification)
- Removed disable-swift.patch

* Wed May 14 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.12.dev1068
- Removed unnecessary hacks (rhbz#1096510)

* Mon May 12 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.11.dev1067
- Ensure sshkey title is unique
- Install ceilometer compute agent on nova-cpu nodes (lp#1318383)
- Added 0001-Workaround-for-stoped-openstack-ceilometer-notificat.patch

* Fri May 9 2014 Iván Chavero <ichavero@redhat.com> - 2014.1.1-0.10.dev1065
- Install o-p-m dependencies on all nodes
- [vCenter] Fix the parameters duplicated in answer file (rhbz#1061372, rhbz#1092008)
- Set correct keystone_default_role for Horizon
- Better localhost checking for SSL configuration
- Add hostname to SSL redirection (rhbz#1078130)
- Introduce support for mocking command output
- [Horizon] Fixed help_url to point to upstream docs (rhbz#1080917)
- Support ssh-based live migration (lp#1311168)
- Introduce support for mocking command output

* Wed Apr 30 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.9.dev1055
- Redirect to https port when SSL enabled (rhbz#1078130)
- Added puppet resource sequence for cinder backup (rhbz#1075609)
- Teach packstack about "could not autoload" errors (lp#1312224)
- Add support for neutron/nova notifications (lp#1306337)
- Ensure that we run token-flush cron job under correct user (rhbz#1071674)

* Mon Apr 7 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.8.dev1045
- Updated Heat templates (rhbz#1084216)
- Use mariadb-galera-server for server package
- Fix QPID config path compatibility (rhbz#1070072)
- Make RabbitMQ default AMQP provider

* Mon Mar 31 2014 Iván Chavero <ichavero@redhat.com> - 2014.1.1-0.7.dev1033
- Changes the mysql charset to utf8 (rhbz#1080595, rhbz#1080355)

* Fri Mar 28 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.6.dev1032
- Explicitly include the firewall module (lp#1297857)
- Fixed MongoDB manifests (lp#1297984, lp#1297995)

* Wed Mar 26 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.5.dev1025
- Ensure ovs_neutron_plugin.ini has correct ownership (rhbz#1080438)
- Disable provisioning for multihost installations (rhbz#bug1080369)
- Removed heat-qpid.patch

* Tue Mar 25 2014 Pádraig Brady <pbrady@redhat.com> - 2014.1.1-0.4.dev1018
- Enable EPEL by default

* Sat Mar 22 2014 Pádraig Brady <pbrady@redhat.com> - 2014.1.1-0.3.dev1018
- Fix failure with heat qpid configuration

* Fri Mar 21 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.2.dev1018
- Added qpid-conf.patch

* Mon Feb 24 2014 Martin Mágr <mmagr@redhat.com> - 2014.1.1-0.1.dev992
- Added openstack-packstack-doc subpackage
- Added openstack-packstack-puppet subpackage (rhbz#1063980)
- Removed packstack-puppet-modules subpackage (rhbz#1063980)
- Added openstack-puppet-modules require (rhbz#1063980)

* Tue Feb 04 2014 Matthias Runge <mrunge@redhat.com> - 2013.2.1-0.30.dev956
- fix build related issue on el7
- fix bogus date in changelogs

* Mon Jan 13 2014 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.29.dev956
- Fixes qpid SSL installation errors (rhbz#1052163, rhbz#1048705)
- Open Keystone port for ALL (rhbz#1041560)

* Fri Jan 10 2014 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.28.dev948
- Move to the upstream puppet-vswitch module
- Add missing example options (rhbz#971745)
- Removed patches since they are not needed anymore
- Install php only with nagios (rhbz#1039660)
- Change puppet-qpid module to upstream (rhbz#1029576)
- Update puppet-neutron to stable/havana which contains fixes for Puppet 3.4+ (lp#1267488)
- Updated puppet-swift to stable/havana (rhbz#1039981)

* Fri Jan 03 2014 Pádraig Brady <pbrady@redhat.com> - 2013.2.1-0.27.dev936
- Don't set libvirt_vif_driver no longer supported by nova (rhbz#1048315)

* Fri Dec 20 2013 Pádraig Brady <pbrady@redhat.com> - 2013.2.1-0.25.dev936
- Use correct syntax to install multiple packages (rhbz#1045283)

* Fri Dec 20 2013 Pádraig Brady <pbrady@redhat.com> - 2013.2.1-0.24.dev936
- Reinstate the V1 API needed by cinder client (rhbz#1043280)
- Use class for notifier strategy (rhbz#1020002)

* Wed Dec 11 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.23.dev934
- CONFIG_NEUTRON_LBAAS_HOSTS should be empty in allinone (rhbz#1040585)
- service_plugins must not be list with empty string (rhbz#1040585)

* Wed Dec 11 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.22.dev930
- Allow Ceilometer API for all hosts (rhbz#1040404)
- Require also core_plugin setting
- Revert "Move packstack logs to /var/log/packstack" due to security reasons

* Tue Dec 10 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.21.dev925
- NEUTRON_LBAAS_HOSTS should be empty by default (rhbz#1040039)

* Tue Dec 10 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.20.dev924
- Adds cinder API v2 endpoint to keystone (rhbz#1030088)
- Upgrades DB before neutron server starts (rhbz#1037675)
- Adds localhost to the list of Horizon's ALLOWED_HOSTS

* Mon Dec 9 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.19.dev919
- Moves packstack logs to /var/log/packstack (#999923)
- Doesn't set up the L3_EXT_BRIDGE twice(rhbz#1000981)
- Updates puppet-nova module (#1015995)
- Adds support for LBaaS agent (#1019780)
- Adds validation for gluster volumes using hostnames (#1020479)
- Validates type of given ssh key (#1022477)
- Doesn't touch NetworkManager and iptables (rhbz#1024292, rhbz#1023955)
- Updates puppet-certmonger module and puppet-pacemaker module (rhbz#1027455)
- Adds puppet-openstack-storage (rhbz#1027460)
- Adds missing options to packstack man page (rhbz#1032103)
- Adds support for cinder::backup::swift (rhbz#1021627)
- Adds auth option to qpid (rhbz#972643)
- Fixes errors when nova is disabled (rhbz#987888, rhbz#1024564, rhbz#1026795)
- Fixes the nova_ceilometer.pp template (rhbz#1032070)
- Fixes heat installer when executed in interactive mode
- Updates puppet-neutron module to latest stable/havana branch (rhbz#1017280)
- Added the help_url pointing to RH doc (rhbz#1030398)

* Tue Dec 3 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.17.dev876
- Add information on location of horizon password (rhbz#1002326)
- Updates puppet-ceilometer module so it won't fails as 2013.2.1-0.16.dev870 do

* Mon Dec 2 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.16.dev870
- Add information on location of horizon password (rhbz#1002326)
- Make network_vlan_ranges available in GRE setups (rhbz#1006534)
- Include the host's FQDN in Horizon's ALLOWED_HOSTS (rhbz#1028678)
- Improve error reporting for shell commands (rhbz#1031786)
- Fixed comments for interactive installation (rhbz#1030767)
- Replace qpid_host with qpid_hostname (lp#1242715)
- Make sure iptables are enabled (rhbz#1023955)
- Align packstack templates with ceilometer upstream git repo (rhbz#1022189)
- Add missing options to packstack man page (rhbz#1032103)
- Disable unsupported features in Horizon for RHOS (rhbz#1035651)

* Thu Nov 14 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.15.dev847
- Use packstack fork of puppet-keystone (rhbz#1022686)

* Wed Nov 13 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.14.dev846
- Module update (rhbz#1026279)

* Mon Nov 4 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.13.dev840
- Update Horizon submodule to the latest (rhbz#988316)
- Fixes EPEL problem (rhbz#1025437)

* Wed Oct 30 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.12.dev835
- Ensure horizon SSL is configured when enabled (rhbz#966094)
- Improves EPEL and RDO repo setup (rhbz#974971, rhbz#990642)
- Ensure Nova Network-compatible demo provisioning (lp#1242668)
- Include Logging and Debug info to packstack docs (rhbz#999929)
- Added Swift hash setting (rhbz#1005727)
- Change msg with Exec resource too (rhbz#1022044)
- Added SSL configuration to qpid (rhbz#1022312)
- Fixes Neutron firewall rule creation on wrong host (#1023561)
- Fixed str formating (rhbz#1022580)
- Use rpm -q --whatprovides as a more general check
- Add puppet-certmonger as a submodule
- Exposes tempest uri/branch selection if provision-tempest is y

* Thu Oct 17 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.11.dev806
- Improved logging (lp#1228187)
- Adds error checking when puppet fails internally (rhbz#958587)
- Store iptables in file when testing netns (rhbz#1016773)
- Got rid of create_resources module (rhbz#961049)
- Creates keystonerc_admin for user (rhbz#964005, rhbz#976394)
- Prescript plugin improvement (rhbz#976787, rhbz#967369)
- Enable optional channel when RHSM is used (rhbz#978651)
- Changes error message in certain cases (rhbz#989334, rhbz#1006476, rhbz#1003959)
- Rephrase support message (rhbz#991801)
- Adds support for multihost nova-network (rhbz#1001916)
- Adds Firewall rules for access to OpenStack components (rhbz#1002063)
- Allows overlapping IPs for Neutron (rhbz#1008863)

* Tue Sep 24 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.10.dev763
- Adds "default-storage-engine=InnoDB" to /etc/my.cnf (#980593)
- Accepts more CLI options (#985361)
- Added GRE support (#1004397)

* Mon Sep 9 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.9.dev756
- Use python-pymongo for EL distros too (#1006401)

* Mon Sep 9 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.8.dev754
- Fixed KeyErrors in case VlanManager is not used (#1006214)

* Mon Sep 9 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.7.dev752
- Cinder fixes

* Mon Sep 9 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.6.dev749
- Added posibility to change Nova network manager (#915365)
- Support for Ceilometer installation (#967310)
- Support for Heat installation (#967309)

* Tue Sep 3 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.5.dev740
- Added python-netaddr depencency

* Mon Sep 2 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.4.dev740
- Added GRE support (#1003120)
- Added MySQL admin password confirmation (#977443)
- Made MySQL installation optional (#890175)
- Persist allinone OVS bridge (#991591)
- Added the haproxy Puppet module
- Default to use emX instead of ethX on Fedora

* Mon Aug 26 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.3.dev722
- Use 3% more space for cinder-volumes (982622)
- Changed the repository for the neutron submodule (#998286)
- Added net.bridge.bridge-nf-call*=1 on compute nodes (#981144)
- Fixed Rawhide support (#995872)
- Inform about support only on RHEL (#975913)
- Use multi validators in CONFIG_SWIFT_PROXY_HOSTS (#928969)
- Correct CIDR values in case of invalid is given (#969977)
- Accept IPv6 address and single IP in range parameters (#949704)

* Tue Aug 13 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.2.dev702
- ovs_use_veth=True is no longer required
- Remove libvirt's default network (i.e. virbr0) to avoid confusion
- Rename Quantum to Neutron
- Added support for configuration of Cinder NFS backend driver (#916301)
- Removed CONFIG_QUANTUM_USE_NAMESPACES option

* Thu Aug 01 2013 Martin Mágr <mmagr@redhat.com> - 2013.2.1-0.1.dev691
- Added support for Cinder GlusterFS backend configuration (#919607)
- Added support for linuxbridge (#971770)
- Service names made more descriptive (#947381)
- Increased timeout of kernel update (#973217)
- Set debug=true for Nova to have some logs (#958152)
- kvm.modules is loaded only if it exists (#979041)

* Thu Aug 01 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.22.dev653
- Enable qpidd on boot (#988803)

* Thu Jul 25 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.21.dev651
- Swithed to https://github.com/packstack/puppet-qpid (#977786)
- If allinone and quantum selected, install basic network (#986024)

* Wed Jul 10 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.20.dev642
- Fixed provider network option (#976380)
- Made token_format configurable (#978853)
- Enable LVM snap autoextend (#975894)
- MariaDB support (#981116)

* Tue Jun 18 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.19.dev632
- Restart openstack-cinder-volume service (#975007)

* Wed Jun 12 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.17.dev631
- Updated Keystone puppet module to have token_format=PKI as default

* Tue Jun 11 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.16.dev630
- Always update kernel package (#972960)

* Mon Jun 10 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.15.dev625
- Omit Nova DB password only on compute nodes (#966325)
- Find free device during host startup (#971145)

* Mon Jun 10 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.14.dev622
- Reverted Nova sql_connection changes because of introduced regression (#966325, #972365)

* Thu Jun 06 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.12.dev621
- Install qemu-kvm before libvirt (#957632)
- Add template for quantum API server (#968513)
- Removed SQL password in sql_connection for compute hosts (#966325)
- Fixed color usage (#971075)
- Activate cinder-volumes VG and scan PVs after reboot (#971145)

* Wed Jun 05 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.9.dev605
- Added whitespace filter to Nova and Quantum plugins (rhbz#970674)
- Removed RDO repo installation procedure

* Tue Jun 04 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.8.dev601
- Updated to packstack-2013.1.1dev601
- Fixes: rhbz#953157, rhbz#966560, rhbz#967291, rhbz#967306, rhbz#967307,
         rhbz#967344, rhbz#967348, rhbz#969975, rhbz#965787

* Thu May 23 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.7.dev580
- Removing call to setenforce (rhbz#954188)
- Synchronize time using all ntp servers (rhbz#956939)
- Fix for nagios multiple installation failures (rhbz#957006)

* Tue Apr 09 2013 Martin Mágr <mmagr@redhat.com> - 2013.1.1-0.4.dev538
- Updated to  packstack-2013.1.1dev538.tar.gz
- Fixes: rhbz#946915, rhbz#947427

* Sun Mar 31 2013 Derek Higgins <derekh@redhat.com> - 2013.1.1-0.3.dev527
- update to packstack-2013.1.1dev527.tar.gz
- no longer require openstack-utils
- packstack now has its own copy of the puppet modules, the symbolic link
  causes problems with package updates

* Fri Mar 15 2013 Derek Higgins <derekh@redhat.com> - 2013.1.1-0.2.dev502
- remove tests

* Fri Mar 15 2013 Derek Higgins <derekh@redhat.com> - 2013.1.1-0.1.dev502
- Udated to grizzly (packstack-2013.1.1dev502.tar.gz)

* Wed Mar 13 2013 Martin Magr <mmagr@redhat.com> - 2012.2.3-0.5.dev475
- Updated to version 2012.2.3dev475

* Wed Feb 27 2013 Martin Magr <mmagr@redhat.com> - 2012.2.3-0.1.dev454
- Updated to version 2012.2.3dev454
- Fixes: rhbz#865347, rhbz#888725, rhbz#892247, rhbz#893107, rhbz#894733,
         rhbz#896618, rhbz#903545, rhbz#903813, rhbz#904670, rhbz#905081,
         rhbz#905368, rhbz#908695, rhbz#908771, rhbz#908846, rhbz#908900,
         rhbz#910089, rhbz#910210, rhbz#911626, rhbz#912006, rhbz#912702,
         rhbz#912745, rhbz#912768, rhbz#915382

* Mon Feb 18 2013 Martin Magr <mmagr@redhat.com> - 2012.2.2-1.0.dev408
- Updated to version 2012.2.2dev408

* Thu Feb 14 2013 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 2012.2.2-0.9.dev406
- Rebuilt for https://fedoraproject.org/wiki/Fedora_19_Mass_Rebuild

* Wed Feb 13 2013 Martin Magr <mmagr@redhat.com> - 2012.2.2-0.8.dev406
- Updated to version 2012.2.2dev406

* Tue Jan 29 2013 Martin Magr <mmagr@redhat.com> - 2012.2.2-0.7.dev346
- Updated to version 2012.2.2dev346

* Mon Jan 28 2013 Martin Magr <mmagr@redhat.com> - 2012.2.2-0.6.dev345
- Updated to version 2012.2.2dev345

* Mon Jan 21 2013 Martin Magr <mmagr@redhat.com> - 2012.2.2-0.5.dev318
- Updated to version 2012.2.2dev318

* Fri Jan 18 2013 Martin Magr <mmagr@redhat.com> - 2012.2.2-0.4.dev315
- Added openstack-utils to Requires
- Updated to version 2012.2.2dev315

* Fri Jan 11 2013 Derek Higgins <derekh@redhat.com> - 2012.2.2-0.3.dev281
- updated to version 2012.2.2dev281

* Fri Dec 07 2012 Derek Higgins <derekh@redhat.com> - 2012.2.2-0.2.dev211
- Fixed packaging, shebang in .sh files was being removed
- updated to version 2012.2.2dev211

* Wed Dec 05 2012 Derek Higgins <derekh@redhat.com> - 2012.2.2-0.1.dev205
- Fixing pre release versioning
- updated to version 2012.2.2dev205

* Fri Nov 30 2012 Derek Higgins <derekh@redhat.com> - 2012.2.1-1dev197
- cleaning up spec file
- updated to version 2012.2.1-1dev197

* Wed Nov 28 2012 Derek Higgins <derekh@redhat.com> - 2012.2.1-1dev186
- example packaging for Fedora / Redhat
