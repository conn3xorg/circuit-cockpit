# Facts give each host's distribution: Debian and Ubuntu install Cockpit
# with apt from backports, the Red Hat family with dnf, and each packages a
# different set of Cockpit's extra pages.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = try(each.value.os, self.os_id) == self.os_id
      error_message = "Host ${each.key} is ${self.os_id}, not the ${try(each.value.os, "")} its os says."
    }

    postcondition {
      condition     = length(setintersection(var.packages, local.not_packaged[lookup(local.os_key, self.os_id, "el")])) == 0
      error_message = "Host ${each.key} is ${self.os_id}, which doesn't package ${join(", ", setintersection(var.packages, local.not_packaged[lookup(local.os_key, self.os_id, "el")]))}. Leave it out of packages for this host."
    }
  }
}

locals {
  # A host object's os stands in for the facts of a host created in the
  # same plan, which can't be read until it exists.
  os     = { for name, h in var.hosts : name => try(h.os, data.conn3x_host.facts[name].os_id) }
  family = { for name, o in local.os : name => contains(["debian", "ubuntu"], o) ? "debian" : "redhat" }

  deb_hosts = { for name, h in var.hosts : name => h if local.family[name] == "debian" }
  rpm_hosts = { for name, h in var.hosts : name => h if local.family[name] == "redhat" }

  # Extra pages each distribution doesn't package. On Rocky Linux and RHEL
  # 10, cockpit-system provides cockpit-networkmanager, -selinux, -kdump
  # and -sosreport, which dnf accepts by those names.
  os_key = { debian = "debian", ubuntu = "ubuntu", fedora = "fedora", rocky = "el", almalinux = "el", rhel = "el", centos = "el" }
  not_packaged = {
    debian = ["cockpit-kdump", "cockpit-ostree", "cockpit-pcp", "cockpit-selinux"]
    ubuntu = ["cockpit-kdump", "cockpit-ostree", "cockpit-selinux"]
    fedora = ["cockpit-pcp"]
    el     = ["cockpit-pcp"]
  }

  packages = distinct(concat(["cockpit"], var.packages))

  # As in Cockpit's install guide: apt-get install -t <codename>-backports,
  # which takes Cockpit and the pages from backports and the rest from the
  # release.
  apt_target = var.backports ? "-t \"$(. /etc/os-release && echo \"$VERSION_CODENAME\")-backports\" " : ""
  apt_install = join(" ", [
    "apt-get update -q &&",
    "DEBIAN_FRONTEND=noninteractive apt-get install -y -q -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confold",
    "${local.apt_target}${join(" ", local.packages)}",
  ])
  apt_installed = "[ \"$(dpkg-query -W -f='$${Status}\\n' ${join(" ", local.packages)} 2>/dev/null | grep -c ' installed$')\" = ${length(local.packages)} ]"

  config = join("\n", compact([
    "# Written by Conn3x. Changes here are overwritten on the next apply.",
    "[WebService]",
    "AllowUnencrypted = ${var.allow_unencrypted}",
    length(var.origins) > 0 ? "Origins = ${join(" ", var.origins)}" : "",
    var.login_title == null ? "" : "LoginTitle = ${var.login_title}",
    var.behind_proxy ? "ProtocolHeader = X-Forwarded-Proto" : "",
    var.behind_proxy ? "ForwardedForHeader = X-Forwarded-For" : "",
  ]))

  # The empty ListenStream drops the unit's own 9090. FreeBind lets the
  # socket bind an address before the network has brought it up at boot.
  listen = join("\n", compact([
    "# Written by Conn3x. Changes here are overwritten on the next apply.",
    "[Socket]",
    "ListenStream=",
    var.address == null ? "ListenStream=${var.port}" : "ListenStream=${strcontains(var.address, ":") ? "[${var.address}]" : var.address}:${var.port}",
    var.address == null ? "" : "FreeBind=yes",
  ]))

  # Cockpit serves the last .crt or .cert in ws-certs.d in alphabetical
  # order, so zz- wins over its own 0-self-signed.cert.
  tls = var.tls_certificate == null ? {} : { crt = var.tls_certificate, key = var.tls_key }
}

# Debian and Ubuntu: Cockpit from backports, which Ubuntu turns on out of the
# box and Debian doesn't.
circuit "cockpit_deb" {
  hosts = local.deb_hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "backports" {
    for_each = var.backports ? ["backports"] : []
    command {
      command = ". /etc/os-release && if [ \"$ID\" = debian ]; then echo \"deb http://deb.debian.org/debian $VERSION_CODENAME-backports main\" > /etc/apt/sources.list.d/backports.list; else echo \"$VERSION_CODENAME-backports isn't in the apt sources. Turn it on, or set backports = false.\" >&2; exit 1; fi"
      unless  = ". /etc/os-release && grep -rqsE \"^[^#]*[[:space:]]$VERSION_CODENAME-backports([[:space:]]|$)\" /etc/apt/sources.list /etc/apt/sources.list.d"
    }
  }

  step "install" {
    command {
      command = local.apt_install
      unless  = local.apt_installed
    }
  }
}

# The Red Hat family: Cockpit from the distribution, and SELinux, which
# decides which ports Cockpit may listen on.
circuit "cockpit_rpm" {
  hosts = local.rpm_hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "packages" {
    for_each = local.packages
    package {
      name = item.value
    }
  }

  step "semanage" {
    for_each = var.port != 9090 ? ["policycoreutils-python-utils"] : []
    package {
      name = item.value
    }
  }

  # A port another service owns in the policy, such as 443, has to be
  # moved with -m.
  step "port" {
    for_each = var.port != 9090 ? [tostring(var.port)] : []
    command {
      command = "semanage port -a -t websm_port_t -p tcp ${item.value} 2>/dev/null || semanage port -m -t websm_port_t -p tcp ${item.value}"
      unless  = "! selinuxenabled || semanage port -l | grep -E '^websm_port_t ' | grep -Eq '[ ,]${item.value}(,|$)'"
    }
  }
}

circuit "cockpit" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "config" {
    file {
      path    = "/etc/cockpit/cockpit.conf"
      content = "${local.config}\n"
    }
    depends_on = [
      conn3x_command.cockpit_deb__install,
      conn3x_package.cockpit_rpm__packages,
      conn3x_command.cockpit_rpm__port,
    ]
    notify = [handler.restart]
  }

  # Cockpit's PAM stack turns away every user named in this file.
  step "root" {
    line {
      path   = "/etc/cockpit/disallowed-users"
      line   = "root"
      regexp = "^root$"
      state  = var.root_login ? "absent" : "present"
      create = true
    }
  }

  step "tls" {
    for_each = local.tls
    link {
      path      = "/etc/cockpit/ws-certs.d/zz-conn3x.${item.key}"
      target    = item.value
      on_remove = "delete"
    }
    notify = [handler.restart]
  }

  step "socket_dir" {
    directory {
      path = "/etc/systemd/system/cockpit.socket.d"
    }
  }

  step "listen" {
    file {
      path    = "/etc/systemd/system/cockpit.socket.d/listen.conf"
      content = "${local.listen}\n"
    }
    notify = [handler.restart]
  }

  step "daemon_reload" {
    command {
      command  = "systemctl daemon-reload"
      triggers = { listen = conn3x_file.cockpit__listen[each.key].revision }
    }
  }

  # Socket activation: systemd listens, and starts cockpit.service on the
  # first connection. The service exits again when nobody is logged in.
  step "socket" {
    service {
      name    = "cockpit.socket"
      state   = "started"
      enabled = true
    }
  }

  handler "restart" {
    service {
      name = "cockpit.socket"
    }
  }
}
