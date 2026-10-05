# UPS monitoring (pve)

OpenTofu config that codifies the UPS monitoring stack already hand-installed, over SSH, on
the bare-metal Proxmox hypervisor `pve` (192.168.50.209) — its own Debian 13 OS, not a VM and
not a Proxmox API object. Applied via `null_resource`/`local-exec` SSH provisioners, the same
pattern `terraform/k3s.tf` uses for k3s version management, since there's no provider for
OS-level package/service config. Manages:

- **NUT (Network UPS Tools)**, monitoring the CyberPower CP900EPFCLCD over USB
  (`usbhid-ups` driver, standalone mode) — `nut-server`/`nut-monitor`/`nut.target`
- `random_password.nut_monuser` — the NUT monitor account password (`/etc/nut/upsd.users`,
  `/etc/nut/upsmon.conf`, and the exporter's env file all converge to this value)
- **nut_exporter** (`github.com/DRuggeri/nut_exporter`) — Prometheus exporter for NUT,
  serving `:9199/ups_metrics`
- **Grafana Alloy** — scrapes `nut_exporter` locally and remote-writes to Grafana Cloud
  Prometheus, consumed by the `grafana_dashboard.ups` / `grafana_rule_group.ups` resources in
  `terraform/grafana`

A known gotcha reproduced here: the UPS was already plugged in when `nut` was first installed,
so NUT's shipped udev rule (group `nut` on the USB device) never auto-applied. The udev
reload+trigger (`nut_udev_refresh`) always runs on every `tofu apply`, independent of whether
anything else changed, since it's cheap and idempotent.

## One-time setup (manual — do this before first `tofu apply`)

Grafana Cloud Prometheus push credentials are not managed by this stack — they're the same
values already used by the in-cluster Alloy agent (`gitops/platform/grafana-cloud`), sourced
from the `grafana-cloud-credentials` Secret in namespace `grafana-cloud` on the promox cluster.
Decrypt that SealedSecret once and export the two values as `TF_VAR_*` (never commit these):

```bash
export TF_VAR_grafana_cloud_prometheus_username="<grafana-cloud-credentials: username>"
export TF_VAR_grafana_cloud_prometheus_password="<grafana-cloud-credentials: password>"
```

SSH key auth to `root@192.168.50.209` must already work (it does — this just reproduces what's
hand-run today).

## Usage

From this stack's directory, using the shared `Makefile.tofu` targets:

```bash
cd k8s-promox/terraform/ups-monitoring
make tofu-r2-bucket   # one-off, only if the shared R2 state bucket doesn't exist yet
make tofu-init
make tofu-plan
make tofu-apply
```

Or from the meta-repo root: `make tofu-plan TF_DIR=k8s-promox/terraform/ups-monitoring`.

## Notes

- `nut_exporter`'s own process telemetry lives at `/metrics`; the NUT data it exports is at
  `/ups_metrics` — the Alloy scrape config and any manual `curl` checks must use the latter.
- `nut_exporter` takes no CLI flags for this setup (an earlier manual attempt passed a wrong
  flag name — it just reads its env vars and listens on `:9199`).
- `/etc/alloy-creds` must stay `chmod 711`, not just the credential files inside it — the
  `alloy` system user can't `local.file` a path it can't traverse into, even if it owns the
  files themselves.
- This stack intentionally has no `provider "proxmox"` block — nothing here is a Proxmox API
  object, so it isn't forced through `bpg/proxmox`'s VM-oriented resources.
- Scoped to this one host on purpose — there's only one Proxmox node with a UPS attached, so
  this doesn't attempt a generic "UPS module for N nodes."
