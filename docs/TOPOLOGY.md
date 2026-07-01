# Cluster Topology

This document describes the physical Proxmox VE layer and the K3s VMs running on
top of it. See [IMPLEMENTATION_PLAN.md](../IMPLEMENTATION_PLAN.md) for how the
infrastructure is provisioned, and [README.md](../README.md) for day-to-day
commands.

## Physical layer: Proxmox VE cluster

The Proxmox hosts form a single VE cluster named `k8s-promox` (`pvecm status`),
sharing corosync/quorum but **not** shared storage — each node's disks are local.

```
                         ┌───────────────────────────┐
                         │   Proxmox VE Cluster       │
                         │      "k8s-promox"          │
                         └──────────────┬──────────────┘
                                        │
              ┌─────────────────────────┴─────────────────────────┐
              │                                                     │
   ┌──────────▼───────────┐                             ┌──────────▼───────────┐
   │  pve  192.168.50.209  │                             │  pve2  192.168.50.211 │
   │  Geekom IT12           │                             │                       │
   │  i7-1280P, 20 threads  │                             │  16 threads, 30 GB RAM│
   │  32 GB RAM             │                             │  storage: local (dir) │
   │  storage: local-zfs    │                             │  storage: local (dir) │
   │  template: 9000        │                             │  template: 9001       │
   └────────────────────┬──┘                             └──────────┬────────────┘
                         │                                            │
        ┌─────────────────┼──────────────────┐              ┌─────────┴─────────┐
        ▼                 ▼                  ▼              ▼                   ▼
  k3s-control       k3s-worker-1       k3s-worker-2   k3s-worker-pve2-1   k3s-worker-pve2-2
  192.168.50.10     192.168.50.11      192.168.50.12  192.168.50.212      192.168.50.213
  2 vCPU / 6 GB     5 vCPU / 10 GB     5 vCPU / 10 GB  7 vCPU / 13 GB      7 vCPU / 13 GB
  (VMID 100)        (VMID 102)         (VMID 101)      (VMID 103)          (VMID 104)
```

`pve2`'s workers are sized for its own capacity (16 threads / ~30.77 GB RAM),
not copied from `pve`'s 5 vCPU / 10 GB sizing — see below.

### Node inventory

| Node   | Host IP         | Role in Proxmox cluster | CPU threads | RAM   | Local storage available              | VMs running |
|--------|-----------------|--------------------------|-------------|-------|----------------------------------------|-------------|
| `pve`  | 192.168.50.209  | Founding member          | 20          | 32 GB | `local` (dir), `local-zfs` (zfspool)  | k3s-control (100), k3s-worker-1 (102), k3s-worker-2 (101), `ubuntu-cloud` template (VMID 9000) |
| `pve2` | 192.168.50.211  | Added member             | 16          | 30 GB | `local` (dir) only — no ZFS pool      | k3s-worker-pve2-1 (103), k3s-worker-pve2-2 (104), `ubuntu-cloud` template (VMID 9001) |

Key difference: **`pve2` has no ZFS-backed storage**, only the default
`local` directory storage. Anything that assumes `local-zfs` (like the
original cloud-init template flow) fails there — this is why storage and
template VMID are tracked per node in both the Makefile registry and
OpenTofu (`storage_pool_pve2` / `template_id_pve2` in
`terraform/variables.tf`), instead of being a single shared value.

### `pve2` capacity: provisioned and joined to K3s

`pve2` runs two VMs (`k3s-worker-pve2-1` / `-2`, VMIDs 103/104), cloned
from its own cloud-init template (VMID 9001, separate from `pve`'s 9000 since
VM IDs are unique cluster-wide). They were provisioned via
`proxmox_virtual_environment_vm.k3s_workers_pve2` in `terraform/main.tf`,
using the `worker_count_pve2` / `worker_ips_pve2` / `proxmox_node_pve2`
variables.

Each worker is sized at **7 vCPU / 13 GB RAM** (`worker_cpu_pve2` /
`worker_memory_pve2` in `terraform/variables.tf`), using nearly all of
`pve2`'s 16 threads / ~30.77 GB RAM: 2×7 = 14 vCPU and 2×13 GB = 26 GB
allocated to VMs, leaving ~2 vCPU / ~4 GB for the Proxmox host itself —
these are deliberately separate variables from `worker_cpu` / `worker_memory`
(which size `pve`'s 5 vCPU / 10 GB workers), since the two hosts have
different capacity. Applying a cpu/memory resize on these particular VMs
took effect live via Proxmox hot-add, without a reboot.

**They are now part of the K3s cluster** (joined via `scripts/install-k3s-worker.sh`,
see `IMPLEMENTATION_PLAN.md` Phase 4) — `kubectl get nodes` on the control
plane lists all five nodes `Ready`.

Avoid passing `--token-file /tmp/...` (or any path under `/tmp`) to the k3s
installer for future joins: the k3s-agent systemd unit can reference that
path for its full lifetime, and `/tmp` doesn't survive a reboot (and
shouldn't be relied on to persist a secret anyway). If a worker's `k3s-agent`
ever gets stuck on boot logging `Waiting for file "..." to be created`,
that's this — check `systemctl cat k3s-agent`'s `ExecStart`/`EnvironmentFile`
for a stale file reference. Safer pattern used here: stage the token as a
transient file *outside* `/tmp` semantics by piping it directly between two
SSH sessions (so the plaintext token never appears in shell history or a
command transcript), e.g.:

```bash
ssh ubuntu@192.168.50.10 "sudo cat /var/lib/rancher/k3s/server/node-token" \
  | ssh ubuntu@192.168.50.212 "sudo tee /tmp/k3s-token >/dev/null && sudo chmod 600 /tmp/k3s-token"
ssh ubuntu@192.168.50.212 "curl -sfL https://get.k3s.io | sudo sh -s - agent \
  --server https://192.168.50.10:6443 --token-file /tmp/k3s-token --node-ip 192.168.50.212 \
  && sudo rm -f /tmp/k3s-token"
```

k3s resolves `--token-file` into a literal `--token` in the persisted
systemd unit at install time, so deleting the staged file immediately after
install is normally safe — but treat any `--token-file` reference to `/tmp`
that's still live *after* install as a bug worth fixing (e.g. via
`systemctl edit k3s-agent` or reinstalling with a literal `--token`).

## Logical layer: K3s cluster

All five VMs sit on the same `192.168.50.0/24` LAN via the `vmbr0` bridge on
their respective Proxmox host, and all five are joined to K3s:

| VM                  | IP              | vCPU | RAM   | Proxmox host | K3s version    | K3s status | Role |
|---------------------|-----------------|------|-------|--------------|-----------------|------------|------|
| `k3s-control`       | 192.168.50.10   | 2    | 6 GB  | `pve`        | v1.35.5+k3s1    | Ready      | Control plane (traefik/servicelb disabled) |
| `k3s-worker-1`      | 192.168.50.11   | 5    | 10 GB | `pve`        | v1.35.5+k3s1    | Ready      | Worker |
| `k3s-worker-2`      | 192.168.50.12   | 5    | 10 GB | `pve`        | v1.35.5+k3s1    | Ready      | Worker |
| `k3s-worker-pve2-1` | 192.168.50.212  | 7    | 13 GB | `pve2`       | v1.36.2+k3s1    | Ready      | Worker |
| `k3s-worker-pve2-2` | 192.168.50.213  | 7    | 13 GB | `pve2`       | v1.36.2+k3s1    | Ready      | Worker |

The K3s layer has no dependency on which Proxmox node a VM runs on — it only
cares about VM IPs. `pve2` joining the Proxmox cluster and hosting new VMs
does not, by itself, extend the K3s cluster; each new worker still needs the
`k3s-agent` join step run against it (see above).

**Known follow-ups, not urgent:**
- Version skew: the `pve2` workers installed the latest stable k3s
  (`v1.36.2+k3s1`) at join time, while the original three nodes are on
  `v1.35.5+k3s1`. Fine short-term (k3s tolerates a minor version gap between
  agent and server), but worth reconciling — either upgrade the older nodes
  or pin `INSTALL_K3S_VERSION` on future joins to match.
- The Proxmox cluster has only 2 nodes and no QDevice/tie-breaker — no HA
  quorum majority if one node drops.
- Still a single K3s control-plane node — no etcd HA (would need 3 for real
  quorum).

## Managing nodes: Makefile

The Makefile keeps a **node registry** so any number of Proxmox nodes can be
managed with the same set of targets. Each node scoped target takes the node
name as a suffix:

```bash
make power-status-pve2          # any registered node
make ssh-pve2
make proxmox-info-pve2
make list-vms-pve2
make check-cloud-init-template-pve2
make create-cloud-init-template-pve2
```

Unsuffixed targets (`make power-status`, `make ssh`, ...) keep working
unchanged and operate on `PROXMOX_DEFAULT_NODE` (`pve`). `*-all` targets
(e.g. `make power-status-all`, `make check-ssh-all`) loop over every
registered node.

### Adding a third node in the future

Edit the registry block at the top of `Makefile`:

```make
PROXMOX_NODES ?= pve pve2 pve3

PROXMOX_HOST_pve3         ?= 192.168.50.220
PROXMOX_STORAGE_pve3      ?= local        # or local-zfs, depending on the host's disk
PROXMOX_TEMPLATE_ID_pve3  ?= 9002         # must be unique cluster-wide
PROXMOX_MAC_pve3          ?=              # optional, for Wake-on-LAN
```

No other Makefile changes are needed — every node-scoped target and `*-all`
target picks up `pve3` automatically.

To also place VMs on the new node via OpenTofu, follow the pattern already
used for `pve2` in `terraform/variables.tf` and `terraform/main.tf`: add
`proxmox_node_pve3` / `template_id_pve3` / `storage_pool_pve3` /
`worker_count_pve3` / `worker_ips_pve3` variables, then a
`proxmox_virtual_environment_vm.k3s_workers_pve3` resource mirroring
`k3s_workers_pve2`. New VMs still need the `k3s-agent` join step (see above)
before they show up in `kubectl get nodes`.
