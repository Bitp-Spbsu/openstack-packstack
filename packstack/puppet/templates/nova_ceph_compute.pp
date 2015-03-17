package { "yum-plugin-priorities":
    ensure => installed,
}->
file { "/etc/yum/pluginconf.d/priorities.conf":
    ensure => present,
}

$rbd_secret_uuid_="$(/bin/cat /root/rbd.secret.uuid | tr \"\\n\" \" \")"

exec { "virsh":
    command => "virsh secret-set-value --secret ${rbd_secret_uuid_} --base64 `/bin/cat client.volumes.key`",
    returns => [ "0", "1", ],
}

exec { "ceph-osd-libvirt-pool":
    command => "ceph osd pool create libvirt-pool 128 128 ; ceph auth get-or-create client.libvirt mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=libvirt-pool'",
    returns => [ "0", "1", ],
    subscribe => Exec ["virsh"],
    refreshonly => true,
}

$ceph_release = "giant"
yumrepo { "ceph-extras":
    descr => "Ceph Extras",
    gpgkey => "https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc",
    enabled => 1,
    baseurl => "http://ceph.com/rpm-${ceph_release}/el$::operatingsystemmajrelease/\$basearch",
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

package { "qemu-kvm":
    ensure => latest,
}
package { "qemu-img":
    ensure => latest,
}
package { "qemu-kvm-tools":
    ensure => latest,
}
package { "qemu-guest-agent":
    ensure => latest,
}

$rbd_secret_uuid=generate("/bin/cat", "/root/rbd.secret.uuid")
nova_config {
  "DEFAULT/rbd_user":                           value => "volumes";
  "DEFAULT/rbd_secret_uuid":                    value => "${rbd_secret_uuid}";
  "libvirt/libvirt_images_type":                value => "rbd";
  "libvirt/libvirt_images_rbd_pool":            value => "volumes";
  "libvirt/libvirt_images_rbd_ceph_conf":       value => "/etc/ceph/ceph.conf";
  "libvirt/libvirt_inject_password":            value => "false";
  "libvirt/libvirt_inject_key":                 value => "false";
  "libvirt/libvirt_inject_partition":           value => "-2";
}->
file { ["/root/client.volumes.key",
        "/root/virsh.result",
        "/root/rbd.secret.uuid"]:
    ensure => absent,
    before => Exec["restart-openstack-nova-compute"],
    require => [ Exec["virsh"],
               Exec["ceph-osd-libvirt-pool"] ]
}
exec { "restart-openstack-nova-compute":
    command => "/etc/init.d/openstack-nova-compute restart",
}
