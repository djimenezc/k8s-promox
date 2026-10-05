# UPS monitoring on the bare-metal Proxmox host (pve, 192.168.50.209).
#
# The CyberPower CP900EPFCLCD is attached via USB directly to the hypervisor's
# own Debian OS — not to a VM, and not a Proxmox API object — so this is
# OS-level package/service config applied over SSH (null_resource/local-exec),
# the same pattern terraform/k3s.tf already uses for k3s version management.
# There is no Terraform provider for NUT/Alloy/a static Go binary, so plain
# ssh is the pragmatic choice.
#
# Every remote script below is written to be safely re-run: apt-get install
# is idempotent, config files are fully overwritten to the desired content
# each time, and systemctl enable --now is a no-op once already enabled/active.
# A null_resource only re-executes its provisioner when its `triggers` change
# (there's no real API object to diff against), so each resource's trigger is
# a hash of the content it's responsible for converging — edit a variable or
# local here and the next `tofu apply` re-runs just that resource against the
# host. File contents are shipped as base64 (`echo <b64> | base64 -d > file`)
# so no shell quoting is needed for values that contain spaces/quotes
# (UPS description, systemd units, the NUT password, River config, ...).

resource "random_password" "nut_monuser" {
  length  = var.nut_monuser_password_length
  special = false # alphanumeric only — also lands in /etc/default/nut_exporter unquoted
}

locals {
  # --- NUT config file contents ------------------------------------------
  nut_conf = <<-EOT
    MODE=standalone
  EOT

  ups_conf = <<-EOT
    [${var.nut_ups_name}]
        driver = usbhid-ups
        port = auto
        desc = "${var.nut_ups_desc}"
  EOT

  upsd_users = <<-EOT
    [monuser]
        password = ${random_password.nut_monuser.result}
        upsmon master
  EOT

  # Full NOTIFYFLAG event set from upsmon.conf.sample, all routed to SYSLOG+WALL.
  nut_notify_events = [
    "ONLINE", "ONBATT", "LOWBATT", "FSD", "COMMOK", "COMMBAD", "SHUTDOWN",
    "REPLBATT", "NOCOMM", "NOPARENT", "CAL", "NOTCAL", "OFF", "NOTOFF",
    "BYPASS", "NOTBYPASS",
  ]

  upsmon_conf = <<-EOT
    MONITOR ${var.nut_ups_name}@localhost 1 monuser ${random_password.nut_monuser.result} master
    MINSUPPLIES 1
    SHUTDOWNCMD "/sbin/shutdown -h +0"
    POLLFREQ 5
    POLLFREQALERT 5
    HOSTSYNC 15
    DEADTIME 15
    NOTIFYCMD /usr/sbin/upssched
    ${join("\n", [for e in local.nut_notify_events : "NOTIFYFLAG ${e} SYSLOG+WALL"])}
    RUN_AS_USER root
  EOT

  # --- nut_exporter --------------------------------------------------------
  nut_exporter_env = <<-EOT
    NUT_EXPORTER_USERNAME=monuser
    NUT_EXPORTER_PASSWORD=${random_password.nut_monuser.result}
    NUT_EXPORTER_SERVER=127.0.0.1
    NUT_EXPORTER_VARIABLES=battery.charge,battery.voltage,battery.voltage.nominal,battery.runtime,input.voltage,input.voltage.nominal,output.voltage,ups.load,ups.status,ups.realpower.nominal
  EOT

  nut_exporter_unit = <<-EOT
    [Unit]
    Description=NUT Prometheus exporter
    After=network.target nut-monitor.service
    Wants=nut-monitor.service

    [Service]
    EnvironmentFile=/etc/default/nut_exporter
    ExecStart=/usr/local/bin/nut_exporter
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
  EOT

  nut_exporter_url = "https://github.com/DRuggeri/nut_exporter/releases/download/v${var.nut_exporter_version}/nut_exporter-v${var.nut_exporter_version}-linux-amd64"

  # --- Grafana Alloy ---------------------------------------------------------
  grafana_apt_repo_line = "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main\n"

  alloy_config = <<-EOT
    local.file "gc_user" {
      filename = "/etc/alloy-creds/gc_user.txt"
    }

    local.file "gc_pass" {
      filename = "/etc/alloy-creds/gc_pass.txt"
    }

    prometheus.scrape "nut" {
      targets         = [{"__address__" = "localhost:9199"}]
      metrics_path    = "/ups_metrics"
      scrape_interval = "${var.alloy_scrape_interval}"
      forward_to      = [prometheus.remote_write.grafanacloud.receiver]
    }

    prometheus.remote_write "grafanacloud" {
      endpoint {
        url = "${var.grafana_cloud_prometheus_url}"
        basic_auth {
          username = local.file.gc_user.content
          password = local.file.gc_pass.content
        }
      }
    }
  EOT

  # --- Remote scripts --------------------------------------------------------
  # Base64 payloads contain only [A-Za-z0-9+/=] — never a shell quote — so the
  # whole script can be safely wrapped in single quotes for the ssh argument
  # without worrying about anything it writes (passwords, "quoted strings",
  # River syntax, ...) breaking out of that quoting.
  nut_remote_script = <<-EOT
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y nut

    echo ${base64encode(local.nut_conf)} | base64 -d > /etc/nut/nut.conf
    echo ${base64encode(local.ups_conf)} | base64 -d > /etc/nut/ups.conf
    echo ${base64encode(local.upsd_users)} | base64 -d > /etc/nut/upsd.users
    echo ${base64encode(local.upsmon_conf)} | base64 -d > /etc/nut/upsmon.conf

    chown root:nut /etc/nut/ups.conf /etc/nut/upsd.users /etc/nut/upsmon.conf
    chmod 640 /etc/nut/ups.conf /etc/nut/upsd.users /etc/nut/upsmon.conf

    systemctl enable --now nut-server nut-monitor nut.target
  EOT

  udev_remote_script = <<-EOT
    set -euo pipefail
    udevadm control --reload-rules
    udevadm trigger --subsystem-match=usb --attr-match=idVendor=${var.nut_usb_vendor_id} --attr-match=idProduct=${var.nut_usb_product_id}
  EOT

  nut_exporter_remote_script = <<-EOT
    set -euo pipefail
    # nut_exporter.service may already be running this exact binary, so write to
    # a temp file and rename() it into place atomically — overwriting the path
    # of a running executable in-place hits ETXTBSY ("text file busy") instead.
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 -o /usr/local/bin/nut_exporter.new ${local.nut_exporter_url}
    chmod +x /usr/local/bin/nut_exporter.new
    mv -f /usr/local/bin/nut_exporter.new /usr/local/bin/nut_exporter

    echo ${base64encode(local.nut_exporter_env)} | base64 -d > /etc/default/nut_exporter
    chmod 600 /etc/default/nut_exporter

    echo ${base64encode(local.nut_exporter_unit)} | base64 -d > /etc/systemd/system/nut_exporter.service

    systemctl daemon-reload
    systemctl enable --now nut_exporter
    systemctl restart nut_exporter
  EOT

  alloy_remote_script = <<-EOT
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y gnupg curl ca-certificates

    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 ${var.alloy_apt_key_url} | gpg --batch --yes --dearmor -o /etc/apt/keyrings/grafana.gpg
    echo ${base64encode(local.grafana_apt_repo_line)} | base64 -d > /etc/apt/sources.list.d/grafana.list

    apt-get update -qq
    apt-get install -y alloy

    install -d -m 0711 /etc/alloy-creds
    echo ${base64encode(var.grafana_cloud_prometheus_username)} | base64 -d > /etc/alloy-creds/gc_user.txt
    echo ${base64encode(var.grafana_cloud_prometheus_password)} | base64 -d > /etc/alloy-creds/gc_pass.txt
    chown alloy:alloy /etc/alloy-creds/gc_user.txt /etc/alloy-creds/gc_pass.txt
    chmod 600 /etc/alloy-creds/gc_user.txt /etc/alloy-creds/gc_pass.txt

    echo ${base64encode(local.alloy_config)} | base64 -d > /etc/alloy/config.alloy

    systemctl enable --now alloy
    systemctl restart alloy
  EOT
}

resource "null_resource" "nut_setup" {
  triggers = {
    content_hash = sha256(join("|", [
      local.nut_conf,
      local.ups_conf,
      local.upsd_users,
      local.upsmon_conf,
    ]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=accept-new ${var.ssh_user}@${var.proxmox_host} '${local.nut_remote_script}'
    EOT
  }
}

# The CyberPower's udev group-nut permission only applies to devices that
# enumerate *after* the rule exists. We hit this already: the UPS was plugged
# in before `nut` was installed, so the shipped rule
# (/lib/udev/rules.d/62-nut-usbups.rules) never auto-applied. Re-running the
# reload+trigger is always safe, so this runs on every apply rather than being
# gated on a content hash.
resource "null_resource" "nut_udev_refresh" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=accept-new ${var.ssh_user}@${var.proxmox_host} '${local.udev_remote_script}'
    EOT
  }

  depends_on = [null_resource.nut_setup]
}

resource "null_resource" "nut_exporter" {
  triggers = {
    content_hash = sha256(join("|", [
      local.nut_exporter_url,
      local.nut_exporter_env,
      local.nut_exporter_unit,
    ]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=accept-new ${var.ssh_user}@${var.proxmox_host} '${local.nut_exporter_remote_script}'
    EOT
  }

  depends_on = [null_resource.nut_setup]
}

resource "null_resource" "alloy" {
  triggers = {
    content_hash = sha256(join("|", [
      local.grafana_apt_repo_line,
      local.alloy_config,
      var.grafana_cloud_prometheus_username,
      var.grafana_cloud_prometheus_password,
    ]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=accept-new ${var.ssh_user}@${var.proxmox_host} '${local.alloy_remote_script}'
    EOT
  }

  depends_on = [null_resource.nut_exporter]
}
