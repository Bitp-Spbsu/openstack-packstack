
class { 'swift::ringbuilder':
  part_power     => '18',
  replicas       => '%(CONFIG_SWIFT_STORAGE_REPLICAS)s',
  min_part_hours => 1,
  require        => Class['swift'],
}

# sets up an rsync db that can be used to sync the ring DB
class { 'swift::ringserver':
  local_net_ip => "%(CONFIG_CONTROLLER_HOST)s",
}

if ($::selinux != "false"){
    selboolean{'rsync_export_all_ro':
        value => on,
        persistent => true,
    }
}
