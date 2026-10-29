variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file, jump_hosts or os."

  validation {
    condition     = alltrue([for h in var.hosts : contains(["debian", "ubuntu", "rocky", "almalinux", "rhel", "centos", "fedora"], try(h.os, "debian"))])
    error_message = "A host object's os must be one of debian, ubuntu, rocky, almalinux, rhel, centos or fedora."
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}
variable "packages" {
  type        = list(string)
  default     = []
  description = "Extra Cockpit pages to install, such as [\"cockpit-podman\", \"cockpit-machines\"]."

  validation {
    condition = alltrue([for p in var.packages : contains([
      "cockpit-files", "cockpit-kdump", "cockpit-machines", "cockpit-networkmanager", "cockpit-ostree", "cockpit-packagekit",
      "cockpit-pcp", "cockpit-podman", "cockpit-selinux", "cockpit-sosreport", "cockpit-storaged",
    ], p)])
    error_message = "Each of packages must be one of cockpit-files, cockpit-kdump, cockpit-machines, cockpit-networkmanager, cockpit-ostree, cockpit-packagekit, cockpit-pcp, cockpit-podman, cockpit-selinux, cockpit-sosreport or cockpit-storaged."
  }
}

variable "backports" {
  type        = bool
  default     = true
  description = "On Debian and Ubuntu, install Cockpit from the release's backports, as Cockpit's own install guide does. On Debian, the circuit adds the backports repository when it's missing."
}

variable "port" {
  type        = number
  default     = 9090
  description = "TCP port Cockpit listens on."

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be a port number from 1 to 65535."
  }
}

variable "address" {
  type        = string
  default     = null
  description = "IP address Cockpit listens on, such as \"127.0.0.1\" behind a reverse proxy. When null, every address."

  validation {
    condition     = var.address == null || can(cidrhost("${coalesce(var.address, "0.0.0.0")}/${strcontains(coalesce(var.address, "-"), ":") ? 128 : 32}", 0))
    error_message = "address must be an IPv4 or IPv6 address, such as \"127.0.0.1\" or \"::1\"."
  }
}

variable "origins" {
  type        = list(string)
  default     = []
  description = "Other origins the browser may reach Cockpit from, such as [\"https://cockpit.example.com\"] behind a reverse proxy. Cockpit always accepts its own address."

  validation {
    condition     = alltrue([for o in var.origins : can(regex("^(https?|wss?)://[^\\s/]+$", o))])
    error_message = "Each of origins must be a scheme and host, with a port if it isn't the default, such as \"https://cockpit.example.com\" or \"https://*.example.com:9090\", without a path."
  }
}

variable "login_title" {
  type        = string
  default     = null
  description = "Browser title for the login page. When null, Cockpit's default, the host name."

  validation {
    condition     = var.login_title == null || !strcontains(coalesce(var.login_title, "-"), "\n")
    error_message = "login_title must be a single line."
  }
}

variable "allow_unencrypted" {
  type        = bool
  default     = false
  description = "Accept plain HTTP from other hosts instead of redirecting it to HTTPS. Only for a reverse proxy that talks HTTP to Cockpit; Cockpit always accepts HTTP from localhost."
}

variable "behind_proxy" {
  type        = bool
  default     = false
  description = "Trust the X-Forwarded-Proto and X-Forwarded-For headers from a reverse proxy. Set it only when nothing but the proxy can reach Cockpit's port."
}

variable "tls_certificate" {
  type        = string
  default     = null
  description = "Path on the host of a PEM certificate, with its chain, for Cockpit to serve, such as \"/etc/letsencrypt/live/cockpit.example.com/fullchain.pem\". When null, Cockpit's self-signed certificate."

  validation {
    condition     = var.tls_certificate == null || can(regex("^/[^\\n]*$", coalesce(var.tls_certificate, "-")))
    error_message = "tls_certificate must be an absolute path."
  }
}

variable "tls_key" {
  type        = string
  default     = null
  description = "Path on the host of the unencrypted private key for tls_certificate, such as \"/etc/letsencrypt/live/cockpit.example.com/privkey.pem\"."

  validation {
    condition     = var.tls_key == null || can(regex("^/[^\\n]*$", coalesce(var.tls_key, "-")))
    error_message = "tls_key must be an absolute path."
  }

  validation {
    condition     = (var.tls_certificate == null) == (var.tls_key == null)
    error_message = "Set both tls_certificate and tls_key, or neither."
  }
}

variable "root_login" {
  type        = bool
  default     = false
  description = "Let root log in to Cockpit with its password. When false, root is in /etc/cockpit/disallowed-users; log in as an administrator and switch to administrative access instead."
}
