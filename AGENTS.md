# k8s-promox

K3s Kubernetes cluster on Proxmox VE, provisioned with OpenTofu. Sub-repo of the
`ai-developer-platform` monorepo — see the parent repo's `CLAUDE.md` for
platform-wide conventions (Trello cards, branch/commit format, agents).

## Layout

| Path | Purpose |
|------|---------|
| `terraform/` | OpenTofu config (`bpg/proxmox` provider). VM resources for the control plane and workers on each Proxmox node, plus `k3s.tf` for version management |
| `scripts/` | Shell scripts for initial K3s bring-up (`install-k3s-control.sh`, `install-k3s-worker.sh`) |
| `docs/TOPOLOGY.md` | Current Proxmox node inventory and K3s VM layout — read this first for "what's actually running" |
| `Makefile` | Proxmox node management (SSH, power, VM/template listing) — node-scoped via a registry, see below |
| `IMPLEMENTATION_PLAN.md` | Original design doc and phased build plan |

## Conventions

- Use `tofu` (OpenTofu), never `terraform` — run via `make tofu-plan` / `make tofu-apply` (targets live in the shared `../Makefile.tofu`).
- The Makefile manages an arbitrary number of Proxmox nodes via a registry (`PROXMOX_NODES` + per-node `PROXMOX_HOST_<node>` etc.). Any node-scoped target works as `make <target>-<node>` (e.g. `make power-status-pve2`); unsuffixed targets act on `PROXMOX_DEFAULT_NODE`. `make help` lists everything.
- K3s version is pinned across the whole cluster by `k3s_version` in `terraform/terraform.tfvars` — bump it and run `make tofu-apply` to upgrade every node (see `terraform/k3s.tf`).
- Before changing node/VM topology, read `docs/TOPOLOGY.md` — it's the source of truth for current state, not the plan doc.
