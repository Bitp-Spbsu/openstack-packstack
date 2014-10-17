Exec { path => "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin" }

$rdo_node = "${hostname}"
$current_dir = "/root"
$basearch = "x86_64"

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
}->
package { "ceph-libs":
    ensure => absent,
}->
file { "/etc/ceph/ceph.conf":
    ensure => present,
}

#echo " --- Create pools"
$poolname1 = "images"
$poolname2 = "volumes"
$poolname3 = "backups"

package { "ceph": ensure => installed}
file { "/var/local/osd0/ready": }
exec { "ceph-create-osd-pool":
    command => "ceph osd pool create ${poolname1} 128 ; ceph osd pool create ${poolname2} 128 ; ceph osd pool create ${poolname3} 128",
    require => Package["ceph"],  
}    

#echo " --- Create a keyring and user for images, volumes and backups"
$keyring_path = "/etc/ceph"

exec { "ceph-key-${poolname1}":
    command => "ceph-authtool --create-keyring ${keyring_path}/ceph.client.${poolname1}.keyring",
    require => Exec["ceph-create-osd-pool"],
}->
file { "/etc/ceph/ceph.client.${poolname1}.keyring":
    mode => "+r",
}->
exec { "ceph-authtool-${poolname1}":
    command => "ceph-authtool ${keyring_path}/ceph.client.${poolname1}.keyring -n client.${poolname1} --gen-key ; ceph-authtool -n client.${poolname1} --cap mon 'allow r' --cap osd 'allow class-read object_prefix rbd_children, allow rwx  pool=${poolname1}' ${keyring_path}/ceph.client.${poolname1}.keyring ; ceph auth add client.${poolname1} -i ${keyring_path}/ceph.client.${poolname1}.keyring",
}

exec { "ceph-key-${poolname2}":
    command => "ceph-authtool --create-keyring ${keyring_path}/ceph.client.${poolname2}.keyring",
    require => Exec["ceph-create-osd-pool"],
}->
file { "/etc/ceph/ceph.client.${poolname2}.keyring":
    mode => "+r",
}->
exec { "ceph-authtool-${poolname2}":
    command => "ceph-authtool ${keyring_path}/ceph.client.${poolname2}.keyring -n client.${poolname2} --gen-key ; ceph-authtool -n client.${poolname2} --cap mon 'allow r' --cap osd 'allow class-read object_prefix rbd_children, allow rwx  pool=${poolname2}' ${keyring_path}/ceph.client.${poolname2}.keyring ; ceph auth add client.${poolname2} -i ${keyring_path}/ceph.client.${poolname2}.keyring",
}

exec { "ceph-key-${poolname3}":
    command => "ceph-authtool --create-keyring ${keyring_path}/ceph.client.${poolname3}.keyring",
    require => Exec["ceph-create-osd-pool"],
}->
file { "/etc/ceph/ceph.client.${poolname3}.keyring":
    mode => "+r",
}->
exec { "ceph-authtool-${poolname3}":
    command => "ceph-authtool ${keyring_path}/ceph.client.${poolname3}.keyring -n client.${poolname3} --gen-key ; ceph-authtool -n client.${poolname3} --cap mon 'allow r' --cap osd 'allow class-read object_prefix rbd_children, allow rwx  pool=${poolname3}' ${keyring_path}/ceph.client.${poolname3}.keyring ; ceph auth add client.${poolname3} -i ${keyring_path}/ceph.client.${poolname3}.keyring",
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

exec { "virsh":
    command => "virsh secret-define --file secret.xml &> virsh.result; cat virsh.result | egrep -o '[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}' > rbd.secret.uuid",
    require => [ #Service["libvirt"],
                 File["/root/secret.xml"],
                 Exec["client-volumes-key"] ],
}

exec { "virsh2":
    command => "virsh secret-set-value --secret `/bin/cat rbd.secret.uuid` --base64 `/bin/cat client.volumes.key`",
    require => Exec ["virsh"],
}
->
file { ["/root/client.volumes.key",
        "/root/virsh.result",
        "/root/rbd.secret.uuid"]:
    ensure => absent,
}

exec { "ceph-osd-libvirt-pool":
    command => "ceph osd pool create libvirt-pool 128 128 ; ceph auth get-or-create client.libvirt mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=libvirt-pool'",
    require =>  Package["ceph"],
                 #Service["libvirt"] ],
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

