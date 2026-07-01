# Control Plane Outputs
output "control_plane_ip" {
  description = "IP address of the control plane node"
  value       = var.control_plane_ip
}

output "control_plane_id" {
  description = "Proxmox VM ID of the control plane"
  value       = try(proxmox_virtual_environment_vm.k3s_control.vm_id, null)
}

# Worker Node Outputs
output "worker_ips" {
  description = "IP addresses of worker nodes"
  value       = [for i in range(var.worker_count) : "${var.worker_ip_prefix}${i + 1}"]
}

output "worker_ids" {
  description = "Proxmox VM IDs of worker nodes"
  value       = try([for vm in proxmox_virtual_environment_vm.k3s_workers : vm.vm_id], [])
}

# pve2 Worker Node Outputs
output "worker_pve2_ips" {
  description = "IP addresses of worker nodes on pve2"
  value       = var.worker_ips_pve2
}

output "worker_pve2_ids" {
  description = "Proxmox VM IDs of worker nodes on pve2"
  value       = try([for vm in proxmox_virtual_environment_vm.k3s_workers_pve2 : vm.vm_id], [])
}

# Cluster Information
output "cluster_nodes" {
  description = "Summary of all cluster nodes"
  value = {
    control_plane = {
      name   = var.control_plane_name
      ip     = var.control_plane_ip
      cpu    = var.control_plane_cpu
      memory = var.control_plane_memory
    }
    workers = concat(
      [
        for i in range(var.worker_count) : {
          name   = "${var.worker_name_prefix}-${i + 1}"
          ip     = "${var.worker_ip_prefix}${i + 1}"
          cpu    = var.worker_cpu
          memory = var.worker_memory
        }
      ],
      [
        for i in range(var.worker_count_pve2) : {
          name   = "${var.worker_name_prefix}-pve2-${i + 1}"
          ip     = var.worker_ips_pve2[i]
          cpu    = var.worker_cpu_pve2
          memory = var.worker_memory_pve2
        }
      ]
    )
  }
}

# SSH Access Information
output "ssh_access" {
  description = "SSH access commands for cluster nodes"
  value = {
    control_plane = "ssh ubuntu@${var.control_plane_ip}"
    workers = concat(
      [
        for i in range(var.worker_count) :
        "ssh ubuntu@${var.worker_ip_prefix}${i + 1}"
      ],
      [
        for i in range(var.worker_count_pve2) :
        "ssh ubuntu@${var.worker_ips_pve2[i]}"
      ]
    )
  }
}