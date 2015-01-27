Exec { path => "/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin" }

#package { "openstack-neutron-ml2":
#    ensure => present,
#}

$local_ip = generate('/bin/hostname', '-i')
file { "/etc/neutron/plugins/ml2/ml2_conf.ini.save":
    ensure => present,
    source => "/etc/neutron/plugins/ml2/ml2_conf.ini",
    require => Package["openstack-neutron-ml2"],
}->
file { "/etc/neutron/plugins/ml2/ml2_conf.ini":
    ensure => present,
    content => 
"[ml2]
type_drivers = gre
tenant_network_types = gre
mechanism_drivers = openvswitch


[ml2_type_flat]


[ml2_type_vlan]


[ml2_type_gre]
tunnel_id_ranges = 1:100


[securitygroup]
firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
enable_security_group = True


[ovs]
local_ip = ${local_ip}
tunnel_type = gre
enable_tunneling = True",
}->
exec { "link-etc-neutron-plugin.ini":
    command => "ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini",
    require => Package["openstack-neutron-ml2"],
    returns => [ "0", "1", ],
}->
exec { "sed-neutron-openswitch":
    command => "sed -i 's,plugins/openvswitch/ovs_neutron_plugin.ini,plugin.ini,g' /etc/init.d/neutron-openvswitch-agent",
    require => Package["openstack-neutron-ml2"],
}

$set_option1 = "/etc/nova/nova.conf DEFAULT  linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver"
$set_option2 = "/etc/neutron/neutron.conf DEFAULT service_plugins router"
$set_option3 = "/etc/neutron/neutron.conf DEFAULT core_plugin ml2"
exec { "openstack-config-set":
    command => "openstack-config --set ${set_option1}; openstack-config --set ${set_option2}; openstack-config --set ${set_option3}",
    require => Exec["sed-neutron-openswitch"],
}

service { "openstack-nova-compute":
    ensure    => running,
    enable    => true,
    subscribe => Exec["openstack-config-set"],
}

exec { "restart-neutron-openvswitch-agent":
    command => "service neutron-openvswitch-agent restart",
    subscribe => Exec["openstack-config-set"],
}

