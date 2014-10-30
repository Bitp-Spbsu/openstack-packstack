
  ## Glance
  $image_name                = 'cirros'
  $image_source              = 'http://download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-disk.img'
  $image_ssh_user            = 'cirros'

  ## Tempest

  $image_name_alt            = false
  $image_source_alt          = false
  $image_ssh_user_alt        = false
  ## Images

  glance_image { $image_name:
    ensure           => present,
    is_public        => 'yes',
    container_format => 'bare',
    disk_format      => 'qcow2',
    source           => $image_source,
  }

  # Support creation of a second glance image
  # distinct from the first, for tempest. It
  # doesn't need to be a different image, just
  # have a different name and ref in glance.
  if $image_name_alt {
    $image_name_alt_real = $image_name_alt
    if ! $image_source_alt {
      # Use the same source by default
      $image_source_alt_real = $image_source
    } else {
      $image_source_alt_real = $image_source_alt
    }

    if ! $image_ssh_user_alt {
      # Use the same user by default
      $image_alt_ssh_user_real = $image_ssh_user
    } else {
      $image_alt_ssh_user_real = $image_ssh_user_alt
    }

    glance_image { $image_name_alt:
      ensure           => present,
      is_public        => 'yes',
      container_format => 'bare',
      disk_format      => 'qcow2',
      source           => $image_source_alt_real,
    }
  } else {
    $image_name_alt_real = $image_name
  }


