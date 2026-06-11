# Proxmox Provider Configuration
variable "proxmox_api_url" {
  description = "Proxmox API endpoint (base URL, without /api2/json — bpg provider appends it)"
  type        = string
  default     = "https://192.168.50.209:8006/"
}

variable "proxmox_token_id" {
  description = "Proxmox API token ID (format: user@realm!tokenname, e.g. root@pam!terraform)"
  type        = string
  default     = "root@pam!terraform"
}

variable "proxmox_token_secret" {
  description = "Proxmox API token secret (UUID). Provided via TF_VAR_proxmox_token_secret."
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name where VMs will be created"
  type        = string
  default     = "pve"
}

# Template Configuration
variable "template_name" {
  description = "Name of the cloud-init template to clone"
  type        = string
  default     = "ubuntu-cloud"
}

variable "template_id" {
  description = "VM ID of the cloud-init template"
  type        = number
  default     = 9000
}

# Network Configuration
variable "network_gateway" {
  description = "Network gateway for VMs"
  type        = string
  default     = "192.168.1.1"
}

variable "network_cidr" {
  description = "CIDR suffix for network configuration"
  type        = number
  default     = 24
}

# SSH Configuration
variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

# Storage Configuration
variable "storage_pool" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "local-zfs"
}

# Control Plane Configuration
variable "control_plane_name" {
  description = "Name for the control plane VM"
  type        = string
  default     = "k3s-control"
}

variable "control_plane_ip" {
  description = "Static IP address for control plane"
  type        = string
  default     = "192.168.1.10"
}

variable "control_plane_cpu" {
  description = "Number of CPU cores for control plane"
  type        = number
  default     = 2
}

variable "control_plane_memory" {
  description = "Memory in MB for control plane"
  type        = number
  default     = 4096
}

variable "control_plane_disk_size" {
  description = "Disk size in GB for control plane"
  type        = number
  default     = 30
}

# Worker Node Configuration
variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "worker_name_prefix" {
  description = "Prefix for worker node names"
  type        = string
  default     = "k3s-worker"
}

variable "worker_ip_prefix" {
  description = "IP address prefix for workers (will append node number)"
  type        = string
  default     = "192.168.1.1"
}

variable "worker_cpu" {
  description = "Number of CPU cores per worker"
  type        = number
  default     = 5
}

variable "worker_memory" {
  description = "Memory in MB per worker"
  type        = number
  default     = 10240
}

variable "worker_disk_size" {
  description = "Disk size in GB for workers"
  type        = number
  default     = 30
}