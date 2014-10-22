Exec { path => "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin" }

$admin_node = "${hostname}" 
$nova_node = "%(CONFIG_COMPUTE_HOSTS)s"
$rdo_node_array = split("${nova_node}", ",")
$current_dir = "/root"
$basearch = "x86_64"

yumrepo { "ceph":
    descr => "Ceph packages for ${basearch}",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-firefly/el6/${basearch}",
    priority => "1",
    gpgcheck => 1,
    ensure => present,
}

yumrepo { "ceph-source":
    descr => "Ceph source packages",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-firefly/el6/SRPMS",
    priority => 1,
    gpgcheck => 1,
    ensure => present,
}

yumrepo { "ceph-noarch":
    descr => "Ceph noarch packages",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-firefly/el6/noarch",
    priority => 1,
    gpgcheck => 1,
    ensure => present,
}

yumrepo { "ceph-extras":
    descr => "Ceph Extras",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-firefly/el6/${basearch}",
    priority => 2,
    gpgcheck => 1,
    ensure => present,
}

yumrepo { "ceph-qemu-source":
    descr => "Ceph Extras Sources",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/packages/ceph-extras/rpm/centos6/SRPMS",
    priority => 2,
    gpgcheck => 1,
    ensure => present,
}

#echo " --- Time sync'ing"
package { "ntp":
    ensure => installed,
}
package { "ntpdate":
    ensure => installed,
}
package { "ntp-doc":
    ensure => installed,
}
exec { "ntpdate":
    command => "ntpdate -b 0.ua.pool.ntp.org",
    require => Package["ntpdate"],
}

#echo " --- Checking ssh server"
package { "openssh-server":
    ensure => installed,
}

#echo " --- Creating ceph user"
user { "ceph":
    ensure => present,
}

#echo " --- Installing RDO"
package { "rdo-release":
    ensure => installed,
    source => "https://rdo.fedorapeople.org/rdo-release.rpm",
}

exec { "yum-update":
    command => "yum update -y",
    require => Package["rdo-release"],
}
package { "ceph-libs":
    ensure => absent,
    require => Exec["yum-update"],
}
package { "ceph-deploy":
    ensure => installed,
    require => Package["ceph-libs"],
}

#echo " --- Deploying new node"
define deploy_nodes() {
    $rdo_node="$(grep -r ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-deploy-new-node-${title}":
        command => "ceph-deploy new ${rdo_node}",
        require => Package["ceph-deploy"],
        timeout => 1800,
    }
}
deploy_nodes{$rdo_node_array:}

#echo " --- Installing CEPH"
exec { "ceph-deploy-admin-install":
    command => "ceph-deploy install ${admin_node}",
    require => Package["ceph-deploy"],
    timeout => 1800,
}

define install_rdo_nodes() {
    $rdo_node="$(grep -r ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-deploy-rdo-install-${title}":
        command => "ceph-deploy install ${rdo_node}",
        require => [ Package["ceph-libs"],
                     Exec["ceph-deploy-new-node-${title}"] ],
        timeout => 1800,
    }
}

install_rdo_nodes{$rdo_node_array:}
#echo " --- Modifying ceph.conf"
file { "/root/ceph.conf":
    ensure => present,
    require => Exec["ceph-deploy-admin-install"],
} -> 
file_line { "Append a line to /root/ceph.conf":
    path => "/root/ceph.conf",  
    line => 
"osd pool default size = 1
public network = 194.44.37.0/24
cluster network = 10.1.1.0/24",
}

#???
/*file { "/etc/ceph/ceph.conf":
    ensure => present,
    source => "/root/ceph.conf",
    require => File["/root/ceph.conf"],
}*/

#echo " --- Adding the initial monitor and gathering the keys"
$monitor_node = $rdo_node_array[0]
exec { "ceph-deploy-monitor-create":
    command => "ceph-deploy --overwrite-conf mon create ${monitor_node}",
    require => Exec["ceph-deploy-rdo-install-${monitor_node}"],
}
exec { "ceph-deploy-monitor-gatherkeys":
    command => "ceph-deploy gatherkeys ${monitor_node}",
    require => Exec["ceph-deploy-monitor-create"],
    creates => [ "${current_dir}/ceph.client.admin.keyring",
                 "${current_dir}/ceph.bootstrap-osd.keyring",
                 "${current_dir}/ceph.bootstrap-mds.keyring" ],
}

file { "/etc/ceph":
    ensure => directory,
}
#echo " --- Creating OSD"
define deploy_osd() {
    $rdo_node="$(grep -r ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-osd-prepare-${title}":
        command => "ceph-deploy --overwrite-conf osd prepare ${rdo_node}:/var/local/osd0",
        require => [ Exec["ceph-deploy-rdo-install-${title}"],
                     Exec["ceph-deploy-monitor-gatherkeys"],
                     File["/etc/ceph"] ],
    }->
    exec { "ceph-deploy-osd-${title}":
        command => "ceph-deploy osd activate ${rdo_node}:/var/local/osd0",
        require => Exec["ceph-osd-prepare-${title}"],
    }->

    #echo " --- Copying the configuration file and admin key"
    exec { "ceph-deploy-admin-${title}":
        command => "ceph-deploy --overwrite-conf admin ${admin_node} ${rdo_node}",
        require => [ Exec["ceph-deploy-monitor-gatherkeys"],
                     Exec["ceph-deploy-osd-${title}"] ],
    }
}
deploy_osd{$rdo_node_array:}->
file { "/etc/ceph/ceph.client.admin.keyring":
    mode => "+r",    
}

define deploy_mds(){
    #echo " --- Adding a Metadata Server"
    $rdo_node="$(grep -r ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-deploy-mds-${title}":
        command => "ceph-deploy --overwrite-conf mds create ${rdo_node}",
        require => [ Exec["ceph-deploy-monitor-gatherkeys"],
                     Exec["ceph-deploy-new-node-${title}"] ],
    }
}
deploy_mds{$rdo_node_array:}->
file_line { "Append2 a line to /root/ceph.conf":
    path => "/root/ceph.conf",
    line =>
"[client.images]
keyring = /etc/ceph/ceph.client.images.keyring

[client.volumes]
keyring = /etc/ceph/ceph.client.volumes.keyring

[client.backups]
keyring = /etc/ceph/ceph.client.backups.keyring",
    require => File["/root/ceph.conf"],
}

define config_push() {
    $rdo_node="$(grep -r ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-config-push-${title}":
        command => "ceph-deploy --overwrite-conf config push ${rdo_node}",
        require => File_line["Append2 a line to /root/ceph.conf"],
    }
}
config_push{$rdo_node_array:}


#echo " --- Solving ceilometer-api dateutil issue"
package { "python-dateutil":
    ensure => latest,
    provider => "pip",
}

firewall { "00000 Ceph monitor on port 6789":
  chain    => "INPUT",
#  iniface  => "eth1",
  proto => "tcp",
#  source   => "10.1.1.0/24",
  dport => "6789",
  action => "accept",
  notify => Exec["iptables-save"]
}

firewall { "00001 Ceph OSDs on port 6800:7100":
  chain    => "INPUT",
#  iniface  => "eth1",
  proto => "tcp",
#  source   => "10.1.1.0/24",
  dport => "6800-7100",
  action => "accept",
  notify => Exec["iptables-save"]
}

exec { "iptables-save":
  command  => "/sbin/iptables-save > /etc/sysconfig/iptables",
  refreshonly => true,
}

