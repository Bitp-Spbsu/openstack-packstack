Exec { path => "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin" }

$admin_node = "${hostname}"
$storage_node = "%(CONFIG_STORAGE_HOST)s"
$storage_node_array = split("${storage_node}", ",")
$current_dir = "/root"
$basearch = "x86_64"

file { "/etc/yum.repos.d/ceph.repo":
    ensure => absent,
}

yumrepo { "ceph":
    descr => "Ceph packages for ${basearch}",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-firefly/el6/${basearch}",
    priority => "1",
    gpgcheck => 1,
    ensure => present,
    require => File["/etc/yum.repos.d/ceph.repo"],
}

yumrepo { "ceph-source":
    descr => "Ceph source packages",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-firefly/el6/SRPMS",
    priority => 1,
    gpgcheck => 1,
    ensure => present,
    require => Yumrepo["ceph"],
}

yumrepo { "ceph-noarch":
    descr => "Ceph noarch packages",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-firefly/el6/noarch",
    priority => 1,
    gpgcheck => 1,
    ensure => present,
    require => Yumrepo["ceph"],
}


yumrepo { "ceph-extras":
    descr => "Ceph Extras",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-firefly/el6/${basearch}",
    priority => 2,
    gpgcheck => 1,
    ensure => present,
    require => Yumrepo["ceph"],
}

yumrepo { "ceph-qemu-source":
    descr => "Ceph Extras Sources",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/packages/ceph-extras/rpm/centos6/SRPMS",
    priority => 2,
    gpgcheck => 1,
    ensure => present,
    require => Yumrepo["ceph"],
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
service { "ntpd":
    ensure => stopped,
}
exec { "ntpdate":
    command => "ntpdate -b 0.ua.pool.ntp.org",
    require => [ Package["ntpdate"],
               Service["ntpd"] ],
}
exec { "ntpd-on":
    command => "/etc/init.d/ntpd start",
    require => Exec["ntpdate"],
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
package { "ceph":
    ensure => installed,
    require => Package["ceph-deploy"],
}

#echo " --- Deploying new node"
define deploy_nodes() {
    $storage_node="$(grep -r ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-deploy-new-node-${title}":
        command => "ceph-deploy new ${storage_node}",
        require => Package["ceph-deploy"],
        timeout => 1800,
    }
}
deploy_nodes{$storage_node_array:}

#echo " --- Installing CEPH"
exec { "ceph-deploy-admin-install":
    command => "ceph-deploy install ${admin_node}",
    require => Package["ceph-deploy"],
    timeout => 1800,
}

define install_storage_nodes() {
    $storage_node="$(grep -r ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-deploy-storage-install-${title}":
        command => "ceph-deploy install ${storage_node}",
        require => [ Package["ceph-libs"],
                     Exec["ceph-deploy-new-node-${title}"] ],
        timeout => 1800,
    }
}

install_storage_nodes{$storage_node_array:}
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

#echo " --- Adding the initial monitor and gathering the keys"
define deploy_monitor() {
    $storage_node="$(grep -r ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-deploy-monitor-create-${title}":
        command => "ceph-deploy --overwrite-conf mon create ${storage_node}",
        require => Exec["ceph-deploy-storage-install-${title}"],
    }
}
$first_node = $storage_node_array[0]
$gather_node = "$(grep -r ${first_node} /etc/hosts | awk '{print \$2}')"
deploy_monitor{$storage_node_array:}
exec { "ceph-deploy-monitor-gatherkeys-${first_node}":
    command => "ceph-deploy gatherkeys ${gather_node}",
    require => Exec["ceph-deploy-monitor-create-${first_node}"],
    creates => [ "${current_dir}/ceph.client.admin.keyring",
                 "${current_dir}/ceph.bootstrap-osd.keyring",
                 "${current_dir}/ceph.bootstrap-mds.keyring" ],
}

file { "/etc/ceph":
    ensure => directory,
}
#echo " --- Creating OSD"
define deploy_osd() {
    $storage_node="$(grep -r ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-osd-prepare-${title}":
        command => "ceph-deploy --overwrite-conf osd prepare ${storage_node}:/var/local/osd0",
        require => [ Exec["ceph-deploy-storage-install-${title}"],
                     Exec["ceph-deploy-monitor-gatherkeys-${first_node}"],
                     File["/etc/ceph"] ],
    }->
    exec { "ceph-deploy-osd-${title}":
        command => "ceph-deploy osd activate ${storage_node}:/var/local/osd0",
        require => Exec["ceph-osd-prepare-${title}"],
    }->

    #echo " --- Copying the configuration file and admin key"
    exec { "ceph-deploy-admin-${title}":
        command => "ceph-deploy --overwrite-conf admin ${admin_node} ${storage_node}",
        require => [ Exec["ceph-deploy-monitor-gatherkeys-${first_node}"],
                     Exec["ceph-deploy-osd-${title}"] ],
    }
}
deploy_osd{$storage_node_array:}->
file { "/etc/ceph/ceph.client.admin.keyring":
    mode => "+r",
}

define deploy_mds(){
    #echo " --- Adding a Metadata Server"
    $storage_node="$(grep -r ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-deploy-mds-${title}":
        command => "ceph-deploy --overwrite-conf mds create ${storage_node}",
        require => [ Exec["ceph-deploy-monitor-gatherkeys-${first_node}"],
                     Exec["ceph-deploy-storage-install-${title}"] ],
    }
}
deploy_mds{$storage_node_array:}->
file_line { "Append keyring info to /root/ceph.conf":
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
    $storage_node="$(grep -r ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-config-push-${title}":
        command => "ceph-deploy --overwrite-conf config push ${storage_node}",
        require => File_line["Append keyring info to /root/ceph.conf"],
    }
}
config_push{$storage_node_array:}


#echo " --- Create pools"
$poolname1 = "images"
$poolname2 = "volumes"
$poolname3 = "backups"

exec { "ceph-create-osd-pool":
    command => "ceph osd pool create ${poolname1} 128 ; ceph osd pool create ${poolname2} 128 ; ceph osd pool create ${poolname3} 128",
    require => [ Package["ceph"],
                 File_line ["Append keyring info to /root/ceph.conf"] ],
}

#echo " --- Create a keyring and user for images, volumes and backups"
$keyring_path = "/etc/ceph"

exec { "ceph-create-key-${poolname1}":
    command => "ceph-authtool --create-keyring ${keyring_path}/ceph.client.${poolname1}.keyring",
    require => Exec["ceph-create-osd-pool"],
}->
file { "/etc/ceph/ceph.client.${poolname1}.keyring":
    mode => "+r",
}->
exec { "ceph-authtool-${poolname1}":
    command => "ceph-authtool ${keyring_path}/ceph.client.${poolname1}.keyring -n client.${poolname1} --gen-key ; ceph-authtool -n client.${poolname1} --cap mon 'allow r' --cap osd 'allow class-read object_prefix rbd_children, allow rwx  pool=${poolname1}' ${keyring_path}/ceph.client.${poolname1}.keyring ; ceph auth import -i ${keyring_path}/ceph.client.${poolname1}.keyring",
}

exec { "ceph-create-key-${poolname2}":
    command => "ceph-authtool --create-keyring ${keyring_path}/ceph.client.${poolname2}.keyring",
    require => Exec["ceph-create-osd-pool"],
}->
file { "/etc/ceph/ceph.client.${poolname2}.keyring":
    mode => "+r",
}->
exec { "ceph-authtool-${poolname2}":
    command => "ceph-authtool ${keyring_path}/ceph.client.${poolname2}.keyring -n client.${poolname2} --gen-key ; ceph-authtool -n client.${poolname2} --cap mon 'allow r' --cap osd 'allow class-read object_prefix rbd_children, allow rwx  pool=${poolname2}' ${keyring_path}/ceph.client.${poolname2}.keyring ; ceph auth import -i ${keyring_path}/ceph.client.${poolname2}.keyring",
}

exec { "ceph-create-key-${poolname3}":
    command => "ceph-authtool --create-keyring ${keyring_path}/ceph.client.${poolname3}.keyring",
    require => Exec["ceph-create-osd-pool"],
}->
file { "/etc/ceph/ceph.client.${poolname3}.keyring":
    mode => "+r",
}->
exec { "ceph-authtool-${poolname3}":
    command => "ceph-authtool ${keyring_path}/ceph.client.${poolname3}.keyring -n client.${poolname3} --gen-key ; ceph-authtool -n client.${poolname3} --cap mon 'allow r' --cap osd 'allow class-read object_prefix rbd_children, allow rwx  pool=${poolname3}' ${keyring_path}/ceph.client.${poolname3}.keyring ; ceph auth import -i ${keyring_path}/ceph.client.${poolname3}.keyring",
}

#echo " --- Configuring Libvirt"
augeas { "sudo/requiretty":
        incl    => "/etc/sudoers",
        lens    => "Sudoers.lns",
        changes => [
                "ins #comment before Defaults[requiretty]",
                "set #comment[following-sibling::Defaults/requiretty][last()] 'Defaults requiretty'",
                "rm Defaults/requiretty",
                "rm Defaults[count(*) = 0]",
        ],
        onlyif => "match Defaults/requiretty size > 0",
        before => Exec["client-volumes-key"],
}
exec { "client-volumes-key":
    command => "ceph auth get-key client.volumes | tee client.volumes.key",
    require => [ #Exec["ceph-authtool-volumes"],
                 Package["ceph"],
                 ],
#    before => Exec["virsh"],
    creates => "/root/client.volumes.key",
}

file { "/root/secret.xml":
  ensure => present,
  content =>
"<secret ephemeral='no' private='no'>
<usage type='ceph'>
  <name>client.volumes secret</name>
</usage>
</secret>",
}

package { "libvirt":
    ensure => installed,
}
service { "libvirtd":
    ensure => running,
    provider => "init",
    require => Package["libvirt"],
}
exec { "virsh":
    command => "virsh secret-define --file secret.xml &> virsh.result; cat virsh.result | egrep -o '[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}' > rbd.secret.uuid",
    returns => [ "0", "1", ],
    require => [ Service["libvirtd"],
                 File["/root/secret.xml"],
                 Exec["client-volumes-key"] ],
}

exec { "virsh2":
    command => "virsh secret-set-value --secret ${rbd_secret_uuid} --base64 `/bin/cat client.volumes.key`",
    returns => [ "0", "1", ],
    require => Exec ["virsh"],
}

exec { "ceph-osd-libvirt-pool":
    command => "ceph osd pool create libvirt-pool 128 128 ; ceph auth get-or-create client.libvirt mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=libvirt-pool'",
    returns => [ "0", "1", ],
    require =>  Package["ceph"],
                 #Service["libvirt"] ],
}

#echo " --- Solving ceilometer-api dateutil issue"
/*package { "python-dateutil":
    ensure => latest,
    provider => "pip",
}*/

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


