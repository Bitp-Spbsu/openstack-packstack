Exec { path => "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin" }

$admin_node = "${hostname}"
$storage_node = "%(CONFIG_CEPH_STORAGE_HOSTS)s"
$storage_node_array = split("${storage_node}", ",")
$grep_prepare=regsubst($storage_node, ',', ' -we ', 'G')
$all_storage_nodes = "grep -we ${grep_prepare} /etc/hosts | awk '{print \$2}' | tr \"\\n\" \" \""
$first_node = $storage_node_array[0]
$gather_node = "$(grep -we ${first_node} /etc/hosts | awk '{print \$2}')"
$current_dir = "/root"
$public_network = "%(CONFIG_CEPH_PUBNETWORK)s"
$cluster_network = "%(CONFIG_CEPH_CLUSTERNETWORK)s"
$mount_point = "%(CONFIG_CEPH_MOUNT_POINT)s"
$ceph_release = "giant"

file { "/etc/yum.repos.d/ceph.repo":
    ensure => absent,
}

yumrepo { "ceph":
    descr => "Ceph packages for \$basearch",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-${ceph_release}/el$::operatingsystemmajrelease/\$basearch",
    priority => "1",
    gpgcheck => 1,
    ensure => present,
    require => File["/etc/yum.repos.d/ceph.repo"],
}

yumrepo { "ceph-source":
    descr => "Ceph source packages",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-${ceph_release}/el$::operatingsystemmajrelease/SRPMS",
    priority => 1,
    gpgcheck => 1,
    ensure => present,
    require => Yumrepo["ceph"],
}

yumrepo { "ceph-noarch":
    descr => "Ceph noarch packages",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-${ceph_release}/el$::operatingsystemmajrelease/noarch",
    priority => 1,
    gpgcheck => 1,
    ensure => present,
    require => Yumrepo["ceph"],
}


yumrepo { "ceph-extras":
    descr => "Ceph Extras",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-${ceph_release}/el$::operatingsystemmajrelease/\$basearch",
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
    require => Package["ntp"],
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

exec { "start":
    command => "echo 'Start installation'",
    onlyif  => "test ! -f /etc/ceph/ceph.conf"
}
#echo " --- Deploying new node"
    exec { "ceph-deploy-new-node":
        command => "ceph-deploy new $(${all_storage_nodes})",
        require => Package["ceph-deploy"],
        subscribe => Exec["start"],
        timeout => 1800,
        refreshonly => true,
    }

#echo " --- Installing CEPH"
exec { "ceph-deploy-admin-install":
    command => "ceph-deploy install ${admin_node}",
    require => Package["ceph-deploy"],
    subscribe => Exec["start"],
    timeout => 1800,
    refreshonly => true,
}

exec { "ceph-deploy-storage-install":
    command => "ceph-deploy install $(${all_storage_nodes})",
    require => Package["ceph-libs"],
    subscribe => Exec["ceph-deploy-new-node"],
    timeout => 1800,
    refreshonly => true,
}

#echo " --- Modifying ceph.conf"
file { "/root/ceph.conf":
    ensure => present,
    subscribe => Exec["ceph-deploy-new-node"],
} ->
file_line { "Append a line to /root/ceph.conf":
    path => "/root/ceph.conf",
    line =>
"osd pool default size = 1
public network = ${public_network}/24
cluster network = ${cluster_network}/24",
    subscribe => File["/root/ceph.conf"],
}

define make_dir() {
    $storage_node="$(grep -we ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-mkdir-${title}":
        command => "ssh ${storage_node} 'mkdir -p ${mount_point}/osd.${title}.0 /etc/ceph /var/lib/ceph/osd /var/lib/ceph/mds'",
        subscribe => Exec["ceph-deploy-storage-install"],
        refreshonly => true,
    }
}
make_dir {$storage_node_array:}

#echo " --- Adding the initial monitor and gathering the keys"
exec { "ceph-deploy-monitor-create":
    command => "mkdir -p /etc/ceph; ceph-deploy --overwrite-conf mon create $(${all_storage_nodes})",
#    subscribe => Exec["ceph-deploy-storage-install"],
    subscribe => Make_dir[$storage_node_array],
    refreshonly => true,
}
exec { "ceph-deploy-monitor-gatherkeys":
    command => "sleep 30; ceph-deploy gatherkeys $(${all_storage_nodes})",
    subscribe => Exec["ceph-deploy-monitor-create"],
    refreshonly => true,
    creates => [ "${current_dir}/ceph.client.admin.keyring",
                 "${current_dir}/ceph.bootstrap-osd.keyring",
                 "${current_dir}/ceph.bootstrap-mds.keyring" ],
}

file { "/etc/ceph":
    ensure => directory,
}
#echo " --- Creating OSD"
define deploy_osd() {
    $storage_node="$(grep -we ${title} /etc/hosts | awk '{print \$2}')"
    exec { "ceph-osd-prepare-${title}":
        command => "ceph-deploy --overwrite-conf osd prepare ${storage_node}:${mount_point}/osd.${title}.0",
        require => [ Exec["ceph-deploy-storage-install"],
                     File["/etc/ceph"] ],
        subscribe => Exec["ceph-deploy-monitor-gatherkeys"],
        refreshonly => true,
    }->
    exec { "ceph-deploy-osd-${title}":
        command => "ceph-deploy osd activate ${storage_node}:${mount_point}/osd.${title}.0",
        subscribe => Exec["ceph-osd-prepare-${title}"],
        refreshonly => true,
    }->
    #echo " --- Copying the configuration file and admin key"
    exec { "ceph-deploy-admin-${title}":
        command => "ceph-deploy --overwrite-conf admin ${admin_node} ${all_storage_nodes}",
        subscribe => Exec["ceph-deploy-osd-${title}"],
        refreshonly => true,
    }
}
deploy_osd{$storage_node_array:}->
file { "/etc/ceph/ceph.client.admin.keyring":
    mode => "+r",
}

#echo " --- Adding a Metadata Server"
exec { "ceph-deploy-mds":
    command => "ceph-deploy --overwrite-conf mds create $(${all_storage_nodes})",
    subscribe => Exec["ceph-deploy-monitor-gatherkeys"],
    require => Exec["ceph-deploy-storage-install"],
    refreshonly => true,
    timeout     => 1800,
}
file_line { "Append keyring info to /root/ceph.conf":
    path => "/root/ceph.conf",
    line =>
"[client.images]
keyring = /etc/ceph/ceph.client.images.keyring

[client.volumes]
keyring = /etc/ceph/ceph.client.volumes.keyring

[client.backups]
keyring = /etc/ceph/ceph.client.backups.keyring",
#    subscribe => File["/etc/ceph/ceph.client.admin.keyring"],
    subscribe => Exec["ceph-deploy-monitor-gatherkeys"],
}

    exec { "ceph-config-push-${title}":
        command => "ceph-deploy --overwrite-conf config push $(${all_storage_nodes})",
        subscribe => File_line["Append keyring info to /root/ceph.conf"],
        refreshonly => true,
    }


#echo " --- Create pools"
$poolname1 = "images"
$poolname2 = "volumes"
$poolname3 = "backups"

exec { "ceph-create-osd-pool":
    command => "ceph osd pool create ${poolname1} 128 ; ceph osd pool create ${poolname2} 128 ; ceph osd pool create ${poolname3} 128",
    require => [ Package["ceph"],
                 Exec["ceph-deploy-storage-install"] ],
    subscribe => Deploy_osd[$storage_node_array] ,
    refreshonly => true,
}

#echo " --- Create a keyring and user for images, volumes and backups"
$keyring_path = "/etc/ceph"

exec { "ceph-create-key-${poolname1}":
    command => "ceph-authtool --create-keyring ${keyring_path}/ceph.client.${poolname1}.keyring",
    subscribe => Exec["ceph-create-osd-pool"],
    refreshonly => true,
}->
file { "/etc/ceph/ceph.client.${poolname1}.keyring":
    mode => "+r",
}->
exec { "ceph-authtool-${poolname1}":
    command => "ceph-authtool ${keyring_path}/ceph.client.${poolname1}.keyring -n client.${poolname1} --gen-key ; ceph-authtool -n client.${poolname1} --cap mon 'allow r' --cap osd 'allow class-read object_prefix rbd_children, allow rwx  pool=${poolname1}' ${keyring_path}/ceph.client.${poolname1}.keyring ; ceph auth import -i ${keyring_path}/ceph.client.${poolname1}.keyring",
    subscribe => Exec["ceph-create-key-${poolname1}"],
    refreshonly => true,
}

exec { "ceph-create-key-${poolname2}":
    command => "ceph-authtool --create-keyring ${keyring_path}/ceph.client.${poolname2}.keyring",
    subscribe => Exec["ceph-create-osd-pool"],
    refreshonly => true,
}->
file { "/etc/ceph/ceph.client.${poolname2}.keyring":
    mode => "+r",
}->
exec { "ceph-authtool-${poolname2}":
    command => "ceph-authtool ${keyring_path}/ceph.client.${poolname2}.keyring -n client.${poolname2} --gen-key ; ceph-authtool -n client.${poolname2} --cap mon 'allow r' --cap osd 'allow class-read object_prefix rbd_children, allow rwx  pool=${poolname2}' ${keyring_path}/ceph.client.${poolname2}.keyring ; ceph auth import -i ${keyring_path}/ceph.client.${poolname2}.keyring",
    subscribe => Exec["ceph-create-key-${poolname2}"],
    refreshonly => true,
}

exec { "ceph-create-key-${poolname3}":
    command => "ceph-authtool --create-keyring ${keyring_path}/ceph.client.${poolname3}.keyring",
    subscribe => Exec["ceph-create-osd-pool"],
    refreshonly => true,
}->
file { "/etc/ceph/ceph.client.${poolname3}.keyring":
    mode => "+r",
}->
exec { "ceph-authtool-${poolname3}":
    command => "ceph-authtool ${keyring_path}/ceph.client.${poolname3}.keyring -n client.${poolname3} --gen-key ; ceph-authtool -n client.${poolname3} --cap mon 'allow r' --cap osd 'allow class-read object_prefix rbd_children, allow rwx  pool=${poolname3}' ${keyring_path}/ceph.client.${poolname3}.keyring ; ceph auth import -i ${keyring_path}/ceph.client.${poolname3}.keyring",
    subscribe => Exec["ceph-create-key-${poolname3}"],
    refreshonly => true,
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
    require => [ Exec["ceph-authtool-volumes"],
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

define copy_secret_uuid() {
    $storage_node="$(grep -we ${title} /etc/hosts | awk '{print \$2}')"
    exec { "copy-secret-uuid-${title}":
        command => "scp /root/rbd.secret.uuid root@${storage_node}:/root/rbd.secret.uuid",
        subscribe => Exec["virsh"],
        refreshonly => true,
    }
}
copy_secret_uuid{$storage_node_array:}
#exec { "virsh2":
#    command => "virsh secret-set-value --secret ${rbd_secret_uuid} --base64 `/bin/cat client.volumes.key`",
#    returns => [ "0", "1", ],
#    subscribe => Exec ["virsh"],
#    refreshonly => true,
#}

#exec { "ceph-osd-libvirt-pool":
#    command => "ceph osd pool create libvirt-pool 128 128 ; ceph auth get-or-create client.libvirt mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=libvirt-pool'",
#    returns => [ "0", "1", ],
#    require =>  Package["ceph"],
#    subscribe => Exec ["virsh2"],
#    refreshonly => true,
#}

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

