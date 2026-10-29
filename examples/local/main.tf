variable "port" {
  type    = number
  default = 2296
}

module "cockpit" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  packages    = ["cockpit-files"]
  login_title = "Conn3x test box"
  origins     = ["https://cockpit.example.test"]
}
