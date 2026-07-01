# K3s Version Management
#
# Initial cluster bring-up (installing k3s for the first time) is manual —
# scripts/install-k3s-control.sh / install-k3s-worker.sh, per
# IMPLEMENTATION_PLAN.md Phase 3/4. Once a node is running k3s, this file
# keeps its version pinned to var.k3s_version: bumping that variable and
# running `tofu apply` re-runs the k3s installer against every node with
# INSTALL_K3S_VERSION set to the new value.
#
# get.k3s.io is idempotent/upgrade-safe when re-run against an existing
# install (it only replaces the binary and restarts the service if the
# version actually changed), so re-applying with an unchanged k3s_version
# is a safe no-op — these resources only re-run when the trigger changes.
#
# There's no Terraform provider for k3s itself, so this uses the standard
# null_resource + local-exec pattern: commands run over the same `ssh`
# access already used to manage these nodes, from the machine running
# `tofu apply` (not a Terraform-managed SSH connection).

resource "null_resource" "k3s_control_version" {
  triggers = {
    version = var.k3s_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      ssh -o StrictHostKeyChecking=accept-new ubuntu@${var.control_plane_ip} \
        "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${var.k3s_version} sudo sh -s - server \
          --disable=traefik --disable=servicelb --write-kubeconfig-mode=644 \
          --node-ip=${var.control_plane_ip} --tls-san=${var.control_plane_ip}"
      ssh ubuntu@${var.control_plane_ip} \
        "sudo k3s kubectl wait --for=condition=Ready node/${var.control_plane_name} --timeout=180s"
    EOT
  }

  depends_on = [proxmox_virtual_environment_vm.k3s_control]
}

resource "null_resource" "k3s_worker_version" {
  count = var.worker_count

  triggers = {
    version = var.k3s_version
    ip      = "${var.worker_ip_prefix}${count.index + 1}"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      IP="${var.worker_ip_prefix}${count.index + 1}"
      TOKEN=$(ssh ubuntu@${var.control_plane_ip} "sudo cat /var/lib/rancher/k3s/server/node-token")
      ssh -o StrictHostKeyChecking=accept-new "ubuntu@$IP" \
        "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${var.k3s_version} sudo sh -s - agent \
          --server https://${var.control_plane_ip}:6443 --token $TOKEN --node-ip $IP"
    EOT
  }

  depends_on = [null_resource.k3s_control_version, proxmox_virtual_environment_vm.k3s_workers]
}

resource "null_resource" "k3s_worker_pve2_version" {
  count = var.worker_count_pve2

  triggers = {
    version = var.k3s_version
    ip      = var.worker_ips_pve2[count.index]
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      IP="${var.worker_ips_pve2[count.index]}"
      TOKEN=$(ssh ubuntu@${var.control_plane_ip} "sudo cat /var/lib/rancher/k3s/server/node-token")
      ssh -o StrictHostKeyChecking=accept-new "ubuntu@$IP" \
        "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${var.k3s_version} sudo sh -s - agent \
          --server https://${var.control_plane_ip}:6443 --token $TOKEN --node-ip $IP"
    EOT
  }

  depends_on = [null_resource.k3s_control_version, proxmox_virtual_environment_vm.k3s_workers_pve2]
}
