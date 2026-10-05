output "proxmox_host" {
  description = "Proxmox host this stack configures UPS monitoring on"
  value       = var.proxmox_host
}

output "nut_ups_name" {
  description = "NUT UPS identifier (ups.conf section name), referenced as <name>@localhost"
  value       = var.nut_ups_name
}

output "nut_exporter_metrics_url" {
  description = "Prometheus metrics endpoint exposed by nut_exporter on the host (scraped locally by Alloy, not exposed off-host)"
  value       = "http://${var.proxmox_host}:9199/ups_metrics"
}

output "nut_monuser_password" {
  description = "Generated NUT monitor (upsd.users) password, for operators who need to query upsd directly (e.g. upsc). Sensitive — not printed by default."
  value       = random_password.nut_monuser.result
  sensitive   = true
}
