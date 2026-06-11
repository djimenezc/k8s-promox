# K3s Control Plane Node
resource "proxmox_virtual_environment_vm" "k3s_control" {
  name      = var.control_plane_name
  node_name = var.proxmox_node

  # Clone from the cloud-init template
  clone {
    vm_id = var.template_id
    full  = true
  }

  # QEMU Guest Agent
  agent {
    enabled = true
  }

  # CPU / Memory
  cpu {
    cores   = var.control_plane_cpu
    sockets = 1
  }

  memory {
    dedicated = var.control_plane_memory
  }

  # Boot disk
  scsi_hardware = "virtio-scsi-pci"

  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    size         = var.control_plane_disk_size
  }

  boot_order = ["scsi0"]

  # Network
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  # Cloud-Init
  initialization {
    datastore_id = var.storage_pool

    ip_config {
      ipv4 {
        address = "${var.control_plane_ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }
}

# K3s Worker Nodes
resource "proxmox_virtual_environment_vm" "k3s_workers" {
  count     = var.worker_count
  name      = "${var.worker_name_prefix}-${count.index + 1}"
  node_name = var.proxmox_node

  # Clone from the cloud-init template
  clone {
    vm_id = var.template_id
    full  = true
  }

  # QEMU Guest Agent
  agent {
    enabled = true
  }

  # CPU / Memory
  cpu {
    cores   = var.worker_cpu
    sockets = 1
  }

  memory {
    dedicated = var.worker_memory
  }

  # Boot disk
  scsi_hardware = "virtio-scsi-pci"

  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    size         = var.worker_disk_size
  }

  boot_order = ["scsi0"]

  # Network
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  # Cloud-Init
  initialization {
    datastore_id = var.storage_pool

    ip_config {
      ipv4 {
        address = "${var.worker_ip_prefix}${count.index + 1}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  # Ensure control plane is created first
  depends_on = [proxmox_virtual_environment_vm.k3s_control]

  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }
}
