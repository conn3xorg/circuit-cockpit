output "urls" {
  description = "Cockpit's address on each host, by name."
  value       = { for name, h in var.hosts : name => "https://${coalesce(var.address, try(h.address, h))}:${var.port}/" }
}
