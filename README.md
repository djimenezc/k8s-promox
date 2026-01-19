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

### OpenTofu Operations
- `make tofu-init` - Initialize OpenTofu
- `make tofu-plan` - Preview infrastructure changes
- `make tofu-apply` - Apply infrastructure changes
- `make tofu-destroy` - Destroy all managed infrastructure

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

See [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) for detailed architecture and implementation phases.

**VM Layout:**
- **k3s-control**: 2 vCPU, 4 GB RAM - Control Plane
- **k3s-worker-1**: 5 vCPU, 10 GB RAM - Worker Node
- **k3s-worker-2**: 5 vCPU, 10 GB RAM - Worker Node

**Total:** 12 vCPU, 24 GB RAM (8 GB reserved for Proxmox host)

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

- [Implementation Plan](./IMPLEMENTATION_PLAN.md) - Detailed implementation guide
- [K3s Documentation](https://docs.k3s.io/)
- [Proxmox OpenTofu/Terraform Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)