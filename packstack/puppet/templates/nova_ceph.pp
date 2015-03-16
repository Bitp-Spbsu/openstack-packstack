Exec { path => "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin" }

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

$rbd_secret_uuid=generate("/bin/cat", "/root/rbd.secret.uuid")
cinder_config {
  "DEFAULT/volume_driver":                      value => "cinder.volume.drivers.rbd.RBDDriver";
  "DEFAULT/rbd_user":                           value => "volumes";
  "DEFAULT/rbd_secret_uuid":                    value => "${rbd_secret_uuid}";
  "DEFAULT/rbd_pool":                           value => "volumes";
  "DEFAULT/rbd_ceph_conf":                      value => "/etc/ceph/ceph.conf";
  "DEFAULT/rbd_flatten_volume_from_snapshot":   value => "false";
  "DEFAULT/rbd_max_clone_depth":                value => "5";
  
  "DEFAULT/backup_driver":                      value => "cinder.backup.drivers.ceph";
  "DEFAULT/backup_ceph_conf":                   value => "/etc/ceph/ceph.conf";
  "DEFAULT/backup_ceph_user":                   value => "cinder-backup";
  "DEFAULT/backup_ceph_pool":                   value => "backups";
  "DEFAULT/backup_ceph_chunk_size":             value => "134217728";
  "DEFAULT/backup_ceph_stripe_unit":            value => "0";
  "DEFAULT/backup_ceph_stripe_count":           value => "0";
  "DEFAULT/restore_discard_excess_bytes":       value => "true";
}->
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
glance_api_config {
  "DEFAULT/default_store": 			value => "rbd";
  "DEFAULT/rbd_store_user": 			value => "images";
  "DEFAULT/rbd_store_pool": 			value => "images";
  "DEFAULT/show_image_direct_url": 		value => "True";
  "DEFAULT/rbd_store_ceph_conf": 		value => "/etc/ceph/ceph.conf";
  "DEFAULT/rbd_store_chunk_size": 		value => "8";
}->
file { ["/root/client.volumes.key",
        "/root/virsh.result",
        "/root/rbd.secret.uuid"]:
    ensure => absent,
    before => Exec["openstack-service-restart"],
    require => [ Exec["virsh"],
               Exec["ceph-osd-libvirt-pool"] ]
}
exec { "openstack-service-restart":
    command => "/usr/bin/openstack-service restart",
}


