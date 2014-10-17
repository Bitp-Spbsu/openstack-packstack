$vmware_backend = '%(CONFIG_VMWARE_BACKEND)s'
if $vmware_backend == 'n' {
  exec { 'libvirtd_reload':
    path => ['/usr/sbin/', '/sbin'],
    command => 'service libvirtd reload',
    logoutput => 'on_failure',
    require => Class['nova::network'],
  }
}
