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
  default     = 6144
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

# pve2 Node Configuration (second cluster member, capacity expansion)
variable "proxmox_node_pve2" {
  description = "Proxmox node name for the second cluster member"
  type        = string
  default     = "pve2"
}

variable "template_id_pve2" {
  description = "VM ID of the cloud-init template on pve2 (separate from pve's template; VMIDs are unique cluster-wide)"
  type        = number
  default     = 9001
}

variable "storage_pool_pve2" {
  description = "Proxmox storage pool for VM disks and cloud-init on pve2 (dir-based, no ZFS pool on this node)"
  type        = string
  default     = "local"
}

variable "worker_count_pve2" {
  description = "Number of worker nodes to run on pve2"
  type        = number
  default     = 2
}

variable "worker_ips_pve2" {
  description = "Static IP addresses for pve2 workers, one per worker (indexed by count)"
  type        = list(string)
  default     = ["192.168.50.212", "192.168.50.213"]
}

# pve2 has its own cpu/memory sizing (distinct from worker_cpu/worker_memory,
# which size pve's workers) since it's a different host with different
# capacity: 16 threads / ~30.77 GB RAM. Reserve 2 vCPU / ~4 GB for the
# Proxmox host itself and split the rest evenly across worker_count_pve2.
variable "worker_cpu_pve2" {
  description = "Number of CPU cores per worker on pve2"
  type        = number
  default     = 7
}

variable "worker_memory_pve2" {
  description = "Memory in MB per worker on pve2"
  type        = number
  default     = 13312
}