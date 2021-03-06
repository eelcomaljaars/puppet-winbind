# Install samba and winbind, and join box to the domain
class winbind (
  $domainadminuser,
  $domainadminpw,
  $domain,
  $realm,
  $createcomputer,
  $machine_password_timeout = 604800,
  $netbiosname = $::netbiosname,
  $nagioschecks = false,
  $winbind_max_domain_connections = 1,
  $winbind_max_clients = 200,
  $osdata = false,
  $smbconf_file = '/etc/samba/smb.conf',
) {

  # Main samba config file
  file { 'smb.conf':
    name    => $smbconf_file,
    mode    => '0644',
    owner   => 'root',
    group   => 'root',
    content => template('winbind/smb.conf.erb'),
    require => Package['samba-client'],
    notify  => [ Exec['add-to-domain'], Service['winbind'] ],
  }

  # Install samba winbind client
  package { [
    'samba-winbind-clients',
    'samba-winbind',
    'samba-client',
  ]:
    ensure  => installed,
  }

  # If createcomputer is defined, prepend it with the argument
  if ($createcomputer) {
    $createcomputerarg = "createcomputer=${createcomputer}"
  }

  # If $osdata=true, populate the string
  if ($osdata) {
    $osdataarg = "osName='${::operatingsystem}' osVer=${::operatingsystemmajrelease}"
  }

  # Add the machine to the domain
  exec { 'add-to-domain':
    command => "net ads join -s ${smbconf_file} -U ${domainadminuser}%${domainadminpw} ${createcomputerarg} ${osdataarg}",
    onlyif  => "wbinfo --own-domain | grep -v ${domain}",
    path    => '/bin:/usr/bin',
    notify  => Service['winbind'],
    require => [ File['smb.conf'], Package['samba-winbind-clients'] ],
  }

  file_line { 'let-winbind-use-custom-smbconf-file':
    path   => '/etc/sysconfig/samba',
    line   => "WINBINDOPTIONS=\" -s ${smbconf_file}\"",
    match  => '^WINBINDOPTIONS=.*$',
    notify => Service['winbind'],
  }

  # Start the winbind service
  service { 'winbind':
    ensure     => running,
    require    => [ File['smb.conf'], Package['samba-winbind'] ],
    subscribe  => File['smb.conf'],
    enable     => true,
    hasstatus  => true,
    hasrestart => true,
  }

  if $nagioschecks == true {
    # Nagios plugin to check for domain membership
    @@nagios_service { "check_ads_${::fqdn}":
      check_command       => 'check_nrpe!check_ads',
      service_description => 'Domain',
      use                 => 'hourly-service',
    }
    @@nagios_servicedependency { "check_ads_${::fqdn}":
      dependent_host_name           => $::fqdn,
      dependent_service_description => 'Domain',
      service_description           => 'NRPE',
    }
  }
}
