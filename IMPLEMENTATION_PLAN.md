# K3s on Proxmox - Implementation Plan

## Overview
Provision a K3s Kubernetes cluster on a Proxmox VE server using Terraform.

**Hardware Specs:**
- Host: Geekom IT12
- CPU: Intel i7-1280P (14 cores / 20 threads)
- RAM: 32 GB
- Hypervisor: Proxmox VE (already installed)

## Cluster Architecture

### VM Layout

| VM Name | vCPU | RAM | Purpose | Notes |
|---------|------|-----|---------|-------|
| k3s-control | 2 | 4 GB | Control Plane | Stable, low load |
| k3s-worker-1 | 5 | 10 GB | Worker Node | Main workload, CI/CD |
| k3s-worker-2 | 5 | 10 GB | Worker Node | Scaling tests, overflow |

**Total Resources:**
- vCPU: 12 (leaves 8 threads for Proxmox host overhead)
- RAM: 24 GB allocated to VMs, 8 GB reserved for Proxmox host
- Storage: ~60-90 GB total (20-30 GB per VM)

### Network Configuration
- Bridge: vmbr0 (default Proxmox bridge)
- IP Allocation: Static IPs via cloud-init
- Suggested CIDR: 192.168.1.0/24 (adjust to your network)
  - k3s-control: 192.168.1.10
  - k3s-worker-1: 192.168.1.11
  - k3s-worker-2: 192.168.1.12

## Prerequisites

### 1. Proxmox Configuration
- [ ] Proxmox VE installed and accessible
- [ ] SSH access to Proxmox host
- [ ] API token created for Terraform
  ```bash
  pveum user add terraform@pve
  pveum aclmod / -user terraform@pve -role Administrator
  pveum user token add terraform@pve terraform-token --privsep=0
  ```
- [ ] Storage pool configured (local-lvm or similar)

### 2. Cloud-Init Template
- [ ] Ubuntu 22.04 cloud image downloaded
- [ ] Cloud-init template VM created in Proxmox
  ```bash
  # Download Ubuntu cloud image
  wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

  # Create template VM (ID 9000)
  qm create 9000 --name ubuntu-cloud --memory 2048 --net0 virtio,bridge=vmbr0
  qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm
  qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
  qm set 9000 --ide2 local-lvm:cloudinit
  qm set 9000 --boot c --bootdisk scsi0
  qm set 9000 --serial0 socket --vga serial0
  qm set 9000 --agent enabled=1
  qm template 9000
  ```

### 3. Local Development Tools
- [ ] Terraform installed (>= 1.5.0)
- [ ] SSH key pair generated for VM access
- [ ] kubectl installed for cluster management

## Terraform Structure

```
k8s-promox/
├── terraform/
│   ├── main.tf              # Main Terraform configuration
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Output values (IPs, kubeconfig)
│   ├── providers.tf         # Provider configuration
│   ├── terraform.tfvars     # Variable values (git-ignored)
│   ├── terraform.tfvars.example  # Example values
│   ├── modules/
│   │   ├── proxmox-vm/      # VM provisioning module
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── k3s-node/        # K3s installation module
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── cloud-init/
│   │       │   ├── control-plane.yaml
│   │       │   └── worker.yaml
│   │       └── outputs.tf
│   └── .gitignore
├── scripts/
│   ├── install-k3s-control.sh   # K3s control plane setup
│   ├── install-k3s-worker.sh    # K3s worker node setup
│   └── get-kubeconfig.sh        # Retrieve kubeconfig
├── docs/
│   └── TROUBLESHOOTING.md
├── IMPLEMENTATION_PLAN.md
└── README.md
```

## Implementation Phases

### Phase 1: Terraform Provider Setup
**Goal:** Configure Terraform to communicate with Proxmox

**Tasks:**
1. Create `providers.tf` with Proxmox provider
2. Configure `variables.tf` with Proxmox endpoint, credentials
3. Create `terraform.tfvars.example` template
4. Test connection with `terraform init` and `terraform plan`

**Key Files:**
- `terraform/providers.tf`
- `terraform/variables.tf`
- `terraform/terraform.tfvars.example`

**Terraform Provider:**
```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }
}
```

### Phase 2: VM Provisioning Module
**Goal:** Create reusable module for Proxmox VM creation

**Tasks:**
1. Create `modules/proxmox-vm` module
2. Define VM parameters (CPU, memory, disk, network)
3. Configure cloud-init for initial setup
4. Add SSH key injection
5. Implement static IP assignment

**Key Considerations:**
- Use cloud-init for initial configuration
- Enable QEMU guest agent
- Use virtio drivers for performance
- Allocate disk space appropriately (20-30 GB per VM)

### Phase 3: K3s Control Plane Setup
**Goal:** Deploy and configure K3s control plane node

**Tasks:**
1. Provision control plane VM (2 vCPU, 4 GB RAM)
2. Create cloud-init config with K3s installation script
3. Configure K3s with:
   - `--disable=traefik` (use own ingress later if needed)
   - `--disable=servicelb` (use MetalLB or similar)
   - `--write-kubeconfig-mode=644`
4. Retrieve and save K3s token for worker nodes
5. Output kubeconfig file

**Cloud-Init Tasks:**
- Update system packages
- Install K3s server
- Configure firewall rules (6443, 10250, etc.)
- Enable K3s service

### Phase 4: K3s Worker Nodes Setup
**Goal:** Deploy and join worker nodes to cluster

**Tasks:**
1. Provision worker VMs (5 vCPU, 10 GB RAM each)
2. Create cloud-init config with K3s agent installation
3. Join workers to control plane using K3s token
4. Verify nodes joined successfully

**Cloud-Init Tasks:**
- Update system packages
- Install K3s agent
- Join cluster using control plane IP and token
- Configure firewall rules

### Phase 5: Post-Deployment Configuration
**Goal:** Finalize cluster setup and validation

**Tasks:**
1. Retrieve kubeconfig from control plane
2. Test kubectl access from local machine
3. Verify all nodes are in Ready state
4. Deploy test workload
5. Document access procedures

**Validation Checks:**
```bash
kubectl get nodes
kubectl get pods -A
kubectl run test --image=nginx
kubectl delete pod test
```

### Phase 6: Documentation and Automation
**Goal:** Create runbooks and automation scripts

**Tasks:**
1. Document deployment procedure
2. Create helper scripts for common operations
3. Add troubleshooting guide
4. Create backup/restore procedures

## Key Terraform Resources

### Proxmox Provider Configuration
```hcl
provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_api_token_id = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure = true
}
```

### VM Resource Example
```hcl
resource "proxmox_vm_qemu" "k3s_node" {
  name        = var.vm_name
  target_node = var.proxmox_node
  clone       = var.template_name

  cores   = var.cpu_cores
  memory  = var.memory_mb

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disk {
    type    = "scsi"
    storage = "local-lvm"
    size    = "30G"
  }

  ipconfig0 = "ip=${var.ip_address}/24,gw=${var.gateway}"

  sshkeys = var.ssh_public_key
}
```

## Cloud-Init Configuration Examples

### Control Plane Node
```yaml
#cloud-config
hostname: k3s-control
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_public_key}

package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - curl

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - curl -sfL https://get.k3s.io | sh -s - server --disable traefik --write-kubeconfig-mode=644
  - until [ -f /var/lib/rancher/k3s/server/node-token ]; do sleep 1; done
```

### Worker Node
```yaml
#cloud-config
hostname: k3s-worker-${index}
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_public_key}

package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - curl

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - curl -sfL https://get.k3s.io | K3S_URL=https://${control_plane_ip}:6443 K3S_TOKEN=${k3s_token} sh -
```

## Network and Firewall Considerations

### Required Ports (K3s)
- **6443**: Kubernetes API server
- **10250**: Kubelet metrics
- **8472**: Flannel VXLAN (if using Flannel)
- **2379-2380**: etcd (control plane only)
- **30000-32767**: NodePort Services

### Proxmox Host Firewall
- Ensure VM-to-VM communication is allowed
- Allow inbound 6443 if accessing API externally

## Storage Considerations

### VM Disk Layout
- OS Disk: 30 GB (sufficient for OS + K3s + container images)
- Consider separate data volumes if needed for persistent workloads

### K3s Storage
- Default: local-path provisioner (uses local disk)
- Consider: Longhorn for distributed storage (requires more resources)
- For this setup: Start with local-path, add Longhorn later if needed

## Resource Monitoring

### Host Resource Management
With 24 GB allocated to VMs and 8 GB reserved for Proxmox host:
- Enable memory ballooning on all VMs for flexibility
- Monitor host memory with `free -h` on Proxmox
- 8 GB buffer provides room for host services and VM overhead
- vCPU allocation (12/20 threads) leaves adequate headroom

### Kubernetes Resource Limits
- Set resource requests/limits on critical workloads
- Monitor with `kubectl top nodes` and `kubectl top pods`
- Use labels/taints if needed to segregate different workload types

## Potential Challenges and Mitigations

### 1. Memory Pressure
**Challenge:** Need to balance VM allocation with Proxmox host requirements
**Mitigation:**
- Use memory ballooning for flexibility
- Current allocation provides 8 GB buffer for Proxmox host
- Monitor and adjust based on actual usage
- Workers have 10 GB each for larger workloads
- Consider swap on VMs as buffer if needed

### 2. K3s Token Retrieval
**Challenge:** Worker nodes need control plane token
**Mitigation:**
- Use Terraform provisioners to retrieve token
- Store token in Terraform output (sensitive)
- Pass token to worker cloud-init via template

### 3. Network Connectivity
**Challenge:** VMs need internet access for K3s installation
**Mitigation:**
- Ensure Proxmox host has NAT configured
- Verify DNS resolution in VMs
- Test with `curl -I https://get.k3s.io`

### 4. Cloud-Init Timing
**Challenge:** K3s installation may take time
**Mitigation:**
- Use depends_on in Terraform for worker nodes
- Add readiness checks before joining workers
- Use retry logic in scripts

## Success Criteria

The implementation will be considered successful when:
- [ ] All 3 VMs are provisioned and running
- [ ] K3s control plane is accessible via kubectl
- [ ] Both worker nodes are joined and in Ready state
- [ ] Test deployment runs successfully
- [ ] Kubeconfig is retrieved and works from local machine
- [ ] Documentation is complete and tested

## Next Steps After Implementation

1. **Storage:** Deploy Longhorn or NFS provisioner for persistent volumes
2. **Ingress:** Install and configure ingress controller (nginx, traefik)
3. **Monitoring:** Deploy Prometheus/Grafana stack
4. **CI/CD:** Setup GitHub Actions runner on one of the worker nodes
5. **Backup:** Implement etcd backup strategy
6. **HA:** Consider adding 2 more control plane nodes (requires more resources)

## Estimated Timeline

- Phase 1: Provider Setup - 30 minutes
- Phase 2: VM Module - 1 hour
- Phase 3: Control Plane - 1 hour
- Phase 4: Worker Nodes - 1 hour
- Phase 5: Validation - 30 minutes
- Phase 6: Documentation - 1 hour

**Total: ~5 hours** (assuming no major blockers)

## References

- [K3s Documentation](https://docs.k3s.io/)
- [Proxmox Terraform Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [Proxmox Cloud-Init Guide](https://pve.proxmox.com/wiki/Cloud-Init_Support)
