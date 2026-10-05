# Proxmox host (bare-metal OS, not a VM)
variable "proxmox_host" {
  description = "IP/hostname of the Proxmox hypervisor node the UPS is physically attached to. This is OS-level config applied over SSH, not a bpg/proxmox VM resource."
  type        = string
  default     = "192.168.50.209"

  validation {
    condition     = can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.proxmox_host)) || can(regex("^[a-zA-Z0-9.-]+$", var.proxmox_host))
    error_message = "proxmox_host must be an IPv4 address or a bare hostname."
  }
}

variable "ssh_user" {
  description = "SSH user on the Proxmox host used to apply this config. Must have root privileges (key auth already set up out of band)."
  type        = string
  default     = "root"
}

# NUT / UPS
variable "nut_ups_name" {
  description = "NUT UPS identifier (the section name in ups.conf, referenced as <name>@localhost elsewhere)"
  type        = string
  default     = "cyberpower"
}

variable "nut_ups_desc" {
  description = "Human-readable UPS description written to ups.conf"
  type        = string
  default     = "CyberPower CP900EPFCLCD"
}

variable "nut_usb_vendor_id" {
  description = "USB vendor ID (lsusb) of the UPS's HID interface, used to re-trigger udev's nut-shipped rule after install. CyberPower reuses this ID across several models; usbhid-ups identifies the real model via HID once running."
  type        = string
  default     = "0764"
}

variable "nut_usb_product_id" {
  description = "USB product ID (lsusb) of the UPS's HID interface, paired with nut_usb_vendor_id for the udev re-trigger"
  type        = string
  default     = "0501"
}

variable "nut_monuser_password_length" {
  description = "Length of the generated NUT monitor (upsd.users) password"
  type        = number
  default     = 24

  validation {
    condition     = var.nut_monuser_password_length >= 16
    error_message = "nut_monuser_password_length should be at least 16 characters."
  }
}

# nut_exporter (Prometheus exporter)
variable "nut_exporter_version" {
  description = "nut_exporter release version to install (github.com/DRuggeri/nut_exporter), without the leading v"
  type        = string
  default     = "3.3.0"
}

# Grafana Alloy
variable "alloy_apt_key_url" {
  description = "URL of Grafana's apt signing key, dearmored into /etc/apt/keyrings/grafana.gpg"
  type        = string
  default     = "https://apt.grafana.com/gpg.key"
}

variable "grafana_cloud_prometheus_url" {
  description = "Grafana Cloud Prometheus remote_write push endpoint that Alloy forwards NUT metrics to"
  type        = string
  default     = "https://prometheus-prod-24-prod-eu-west-2.grafana.net/api/prom/push"
}

variable "grafana_cloud_prometheus_username" {
  description = "Grafana Cloud Prometheus remote_write username (instance ID). Same value already used by the in-cluster Alloy agent — copy it once from the `grafana-cloud-credentials` Secret (namespace grafana-cloud, promox cluster) into .env as TF_VAR_grafana_cloud_prometheus_username. Never hardcode."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.grafana_cloud_prometheus_username) > 0
    error_message = "grafana_cloud_prometheus_username must not be empty — set TF_VAR_grafana_cloud_prometheus_username."
  }
}

variable "grafana_cloud_prometheus_password" {
  description = "Grafana Cloud Prometheus remote_write password (API key). Same value already used by the in-cluster Alloy agent — copy it once from the `grafana-cloud-credentials` Secret (namespace grafana-cloud, promox cluster) into .env as TF_VAR_grafana_cloud_prometheus_password. Never hardcode."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.grafana_cloud_prometheus_password) > 0
    error_message = "grafana_cloud_prometheus_password must not be empty — set TF_VAR_grafana_cloud_prometheus_password."
  }
}

variable "alloy_scrape_interval" {
  description = "Interval Alloy scrapes the local nut_exporter at"
  type        = string
  default     = "15s"
}
