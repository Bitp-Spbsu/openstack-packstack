include concat::setup

$horizon_packages = ["python-memcached", "python-netaddr"]

package {$horizon_packages:
    notify => Class["horizon"],
    ensure => present,
}

class {'horizon':
  secret_key => '%(CONFIG_HORIZON_SECRET_KEY)s',
  keystone_host => '%(CONFIG_CONTROLLER_HOST)s',
  keystone_default_role => '_member_',
  #fqdn => ['%(CONFIG_CONTROLLER_HOST)s', "$::fqdn", 'localhost'],
  # TO-DO: Parameter fqdn is used both for ALLOWED_HOSTS in settings_local.py
  #        and for ServerAlias directives in vhost.conf which is breaking server
  #        accessibility. We need ALLOWED_HOSTS values, but we have to avoid
  #        ServerAlias definitions. For now we will use this wildcard hack until
  #        puppet-horizon will have separate parameter for each config.
  fqdn => '*',
  can_set_mount_point => 'False',
  django_debug => %(CONFIG_DEBUG_MODE)s ? {true => 'True', false => 'False'},
  listen_ssl => %(CONFIG_HORIZON_SSL)s,
  horizon_cert => '/etc/pki/tls/certs/ssl_ps_server.crt',
  horizon_key => '/etc/pki/tls/private/ssl_ps_server.key',
  horizon_ca => '/etc/pki/tls/certs/ssl_ps_chain.crt',
  neutron_options => {
    'enable_lb' => %(CONFIG_HORIZON_NEUTRON_LB)s,
    'enable_firewall' => %(CONFIG_HORIZON_NEUTRON_FW)s
  },
}

if %(CONFIG_HORIZON_SSL)s {
  file {'/etc/pki/tls/certs/ps_generate_ssl_certs.ssh':
    content => template('packstack/ssl/generate_ssl_certs.sh.erb'),
    ensure => present,
    mode => '755',
  }

  exec {'/etc/pki/tls/certs/ps_generate_ssl_certs.ssh':
    require => File['/etc/pki/tls/certs/ps_generate_ssl_certs.ssh'],
    notify  => Service['httpd'],
    before  => Class['horizon'],
  }

  apache::listen { '443': }

  # little bit of hatred as we'll have to patch upstream puppet-horizon
  file_line {'horizon_ssl_wsgi_fix':
    path    => '/etc/httpd/conf.d/15-horizon_ssl_vhost.conf',
    match   => 'WSGIProcessGroup.*',
    line    => '  WSGIProcessGroup horizon-ssl',
    require => File['15-horizon_ssl_vhost.conf'],
    notify  => Service['httpd'],
  }
}

class {'memcached':}

$firewall_port = %(CONFIG_HORIZON_PORT)s

firewall { "001 horizon ${firewall_port}  incoming":
    proto    => 'tcp',
    dport    => [%(CONFIG_HORIZON_PORT)s],
    action   => 'accept',
}

if ($::selinux != "false"){
    selboolean{'httpd_can_network_connect':
        value => on,
        persistent => true,
    }
}
