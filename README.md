# K3s on Proxmox

Provision a K3s Kubernetes cluster on Proxmox VE using OpenTofu.

## Quick Start

### 1. Configure Environment

Copy the example environment file and add your API token:

```bash
cp .env.example .env
# Edit .env and add your PROXMOX_TOKEN_SECRET
```

### 2. Verify Connections

Check SSH and API connectivity:

```bash
# Check all connections and dependencies
make check-all

# Or check individually
make check-ssh                    # Test SSH connection
make check-api PROXMOX_TOKEN_SECRET=your-token  # Test API token
make check-dependencies           # Check required tools
```

If you need to load environment variables from .env:

```bash
export $(cat .env | xargs) && make check-api
```

### 3. Setup Proxmox

Get Proxmox system information:

```bash
make proxmox-info
```

Check if cloud-init template exists:

```bash
make check-cloud-init-template
```

Create cloud-init template if needed:

```bash
make create-cloud-init-template
```

### 4. Deploy Cluster

```bash
# Initialize OpenTofu
make tofu-init

# Preview changes
make tofu-plan

# Apply configuration
make tofu-apply
```

## Available Commands

Run `make help` to see all available commands:

```bash
make help
```

### Connection Management
- `make check-all` - Run all connectivity checks
- `make check-ssh` - Verify SSH connection
- `make check-api` - Verify API token (requires PROXMOX_TOKEN_SECRET)
- `make ssh` - SSH into Proxmox host

### Proxmox Information
- `make proxmox-info` - Get system information
- `make list-vms` - List all VMs
- `make list-templates` - List VM templates
- `make check-cloud-init-template` - Check if template exists
- `make create-cloud-init-template` - Create Ubuntu 22.04 cloud-init template

### Multi-Node Management

The cluster's Proxmox hosts are tracked in a node registry (`PROXMOX_NODES` in
the Makefile — see [docs/TOPOLOGY.md](./docs/TOPOLOGY.md)). Every command
above has a node-scoped equivalent by appending `-<node>`, and unsuffixed
commands operate on the default node (`pve`):

```bash
make power-status-pve2      # any target ending in -% works per node
make ssh-pve2
make proxmox-info-pve2
make power-status-all       # loop over every registered node
make check-ssh-all
```

Run `make help` to see the full list, including per-node targets.

### OpenTofu Operations
- `make tofu-init` - Initialize OpenTofu
- `make tofu-plan` - Preview infrastructure changes
- `make tofu-apply` - Apply infrastructure changes
- `make tofu-destroy` - Destroy all managed infrastructure

### K3s Version Management

The k3s version running on every node is pinned via `k3s_version` in
`terraform/terraform.tfvars` (see `terraform/k3s.tf`). To upgrade the whole
cluster: bump `k3s_version`, then `make tofu-plan` / `make tofu-apply` —
this re-runs the k3s installer against the control plane first, then every
worker, with `INSTALL_K3S_VERSION` pinned to the new value. Re-applying with
an unchanged version is a no-op.

## Configuration

### Environment Variables

Set these in `.env` file or export them:

```bash
PROXMOX_HOST=192.168.50.209           # Proxmox host IP
PROXMOX_PORT=8006                      # Proxmox API port
PROXMOX_USER=root                      # SSH user
PROXMOX_TOKEN_ID=terraform@pve!terraform-token
PROXMOX_TOKEN_SECRET=your-secret-here  # Your API token secret
```

### SSH Setup

For passwordless SSH access:

```bash
# Generate SSH key if you don't have one
ssh-keygen -t rsa -b 4096

# Copy key to Proxmox
ssh-copy-id root@192.168.50.209
```

## Cluster Architecture

See [docs/TOPOLOGY.md](./docs/TOPOLOGY.md) for the full Proxmox node inventory
and K3s VM layout, and [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) for
detailed architecture and implementation phases.

**VM Layout:**
- **k3s-control**: 2 vCPU, 6 GB RAM - Control Plane (on `pve`)
- **k3s-worker-1**: 5 vCPU, 10 GB RAM - Worker Node (on `pve`)
- **k3s-worker-2**: 5 vCPU, 10 GB RAM - Worker Node (on `pve`)
- **k3s-worker-pve2-1**: 7 vCPU, 13 GB RAM - Worker Node (on `pve2`)
- **k3s-worker-pve2-2**: 7 vCPU, 13 GB RAM - Worker Node (on `pve2`)

**Total:** 26 vCPU, 52 GB RAM across both Proxmox hosts — see
[docs/TOPOLOGY.md](./docs/TOPOLOGY.md) for the per-host breakdown.

## Troubleshooting

### SSH Connection Fails

```bash
# Test SSH manually
ssh root@192.168.50.209

# If prompted for password, set up SSH keys
ssh-copy-id root@192.168.50.209
```

### API Token Verification Fails

```bash
# Test API token manually
curl -k -H "Authorization: PVEAPIToken=terraform@pve!terraform-token=YOUR-SECRET" \
  https://192.168.50.209:8006/api2/json/version

# Check token in Proxmox UI:
# Datacenter -> Permissions -> API Tokens
```

### Cloud-Init Template Issues

```bash
# Remove existing template and recreate
ssh root@192.168.50.209 "qm destroy 9000"
make create-cloud-init-template
```

## Documentation

- [Topology](./docs/TOPOLOGY.md) - Proxmox node inventory and K3s VM layout
- [Implementation Plan](./IMPLEMENTATION_PLAN.md) - Detailed implementation guide
- [K3s Documentation](https://docs.k3s.io/)
- [Proxmox OpenTofu/Terraform Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)