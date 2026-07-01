# Proxmox K3s Cluster - Makefile
# Verify connections and manage infrastructure

# Generic OpenTofu workflow targets (tofu-init/plan/apply/apply-auto/destroy/clean)
# live in the meta-repo root and are shared with the cloudflare sub-repo.
# TF_DIR defaults to ./terraform, so `make tofu-plan` here acts on this repo.
include ../Makefile.tofu

# Proxmox Node Registry
# Every physical Proxmox VE host is registered here by name. To add a new
# node later:
#   1. Append its name to PROXMOX_NODES
#   2. Define PROXMOX_HOST_<node>        (required)
#   3. Define PROXMOX_STORAGE_<node>     (required — VM disk storage is local per node, not shared)
#   4. Define PROXMOX_TEMPLATE_ID_<node> (required — VMIDs are unique cluster-wide, so each
#                                          node needs its own cloud-init template VMID)
#   5. Define PROXMOX_MAC_<node>         (optional, needed for power-on-<node>)
# All node-scoped targets below (ssh-<node>, power-status-<node>, ...) and
# the *-all targets pick up new nodes automatically — no other changes needed.
PROXMOX_NODES ?= pve pve2

PROXMOX_HOST_pve  ?= 192.168.50.209
PROXMOX_HOST_pve2 ?= 192.168.50.211

# pve has a ZFS-backed root pool; pve2's disk is not a ZFS pool, so it only
# has the dir-based "local" storage available.
PROXMOX_STORAGE_pve  ?= local-zfs
PROXMOX_STORAGE_pve2 ?= local

# VM 9000 already exists (as the template) on pve — pve2 needs a distinct ID.
PROXMOX_TEMPLATE_ID_pve  ?= 9000
PROXMOX_TEMPLATE_ID_pve2 ?= 9001

PROXMOX_MAC_pve  ?=
PROXMOX_MAC_pve2 ?=

# Node used by the unsuffixed targets (ssh, power-status, ...) and by the
# OpenTofu-facing config below, so existing usage keeps working unchanged.
PROXMOX_DEFAULT_NODE ?= pve

# Proxmox Configuration
PROXMOX_HOST ?= $(PROXMOX_HOST_$(PROXMOX_DEFAULT_NODE))
PROXMOX_PORT ?= 8006
PROXMOX_USER ?= root
PROXMOX_STORAGE ?= $(PROXMOX_STORAGE_$(PROXMOX_DEFAULT_NODE))
PROXMOX_API_URL = https://$(PROXMOX_HOST):$(PROXMOX_PORT)/api2/json

# API Token Configuration (override with environment variables or create .env file)
# Format: user@realm!tokenid
PROXMOX_TOKEN_ID ?= root@pam!terraform
PROXMOX_TOKEN_SECRET ?=

# K3s Cluster Configuration
VM_USER ?= ubuntu
CONTROL_PLANE_IP ?= 192.168.50.10
# Write kubeconfig into the parent meta-repo so direnv (.envrc) can export it
KUBECONFIG_OUT ?= ../kubeconfig

# Power Management Configuration
# Optional: Broadcast address (defaults to 255.255.255.255), shared across nodes
PROXMOX_BROADCAST ?= 255.255.255.255

# Colors for output
GREEN := \033[0;32m
RED := \033[0;31m
YELLOW := \033[0;33m
NC := \033[0m # No Color

.PHONY: help
help: ## Show this help message
	@echo "Proxmox K3s Cluster - Available targets:"
	@echo ""
	@grep -hE '^[a-zA-Z0-9_%-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-24s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Node-scoped targets (ssh-%, power-status-%, ...) take a node name from:"
	@echo "  PROXMOX_NODES: $(PROXMOX_NODES)"
	@echo "  e.g. make power-status-pve2"
	@echo ""
	@echo "Configuration:"
	@echo "  PROXMOX_HOST: $(PROXMOX_HOST) (default node: $(PROXMOX_DEFAULT_NODE))"
	@echo "  PROXMOX_PORT: $(PROXMOX_PORT)"
	@echo "  PROXMOX_USER: $(PROXMOX_USER)"
	@echo ""

.PHONY: check-all
check-all: check-ssh check-api check-dependencies ## Run all connectivity checks (default node)

.PHONY: check-ssh-%
check-ssh-%: ## Verify SSH connection to a specific Proxmox node (e.g. make check-ssh-pve2)
	@host="$(PROXMOX_HOST_$*)"; \
	if [ -z "$$host" ]; then \
		printf "$(RED)✗ Unknown Proxmox node '$*' (add it to PROXMOX_NODES)$(NC)\n"; \
		exit 1; \
	fi; \
	printf "$(YELLOW)Testing SSH connection to $* ($$host)...$(NC)\n"; \
	if ssh -o ConnectTimeout=5 -o BatchMode=yes $(PROXMOX_USER)@$$host "exit" 2>/dev/null; then \
		printf "$(GREEN)✓ SSH connection successful$(NC)\n"; \
	else \
		printf "$(RED)✗ SSH connection failed$(NC)\n"; \
		printf "$(YELLOW)Hint: Run 'ssh-copy-id $(PROXMOX_USER)@$$host' to set up key-based authentication$(NC)\n"; \
		exit 1; \
	fi

.PHONY: check-ssh
check-ssh: check-ssh-$(PROXMOX_DEFAULT_NODE) ## Verify SSH connection to the default Proxmox node

.PHONY: check-ssh-all
check-ssh-all: ## Verify SSH connection to every registered Proxmox node
	@for node in $(PROXMOX_NODES); do $(MAKE) check-ssh-$$node || exit 1; done

.PHONY: check-api
check-api: ## Verify Proxmox API token
	@printf "$(YELLOW)Testing Proxmox API token...$(NC)\n"
	@if [ -z "$(PROXMOX_TOKEN_SECRET)" ]; then \
		printf "$(RED)✗ PROXMOX_TOKEN_SECRET not set$(NC)\n"; \
		printf "$(YELLOW)Usage: make check-api PROXMOX_TOKEN_SECRET=your-token-here$(NC)\n"; \
		exit 1; \
	fi
	@response=$$(curl -s -k -w "\n%{http_code}" \
		-H "Authorization: PVEAPIToken=$(PROXMOX_TOKEN_ID)=$(PROXMOX_TOKEN_SECRET)" \
		$(PROXMOX_API_URL)/version); \
	http_code=$$(echo "$$response" | tail -n1); \
	body=$$(echo "$$response" | sed '$$d'); \
	if [ "$$http_code" = "200" ]; then \
		printf "$(GREEN)✓ API token is valid$(NC)\n"; \
		printf "Proxmox version: %s\n" "$$(echo $$body | grep -o '"version":"[^"]*"' | cut -d'"' -f4)"; \
	else \
		printf "$(RED)✗ API token verification failed (HTTP $$http_code)$(NC)\n"; \
		printf "Response: %s\n" "$$body"; \
		exit 1; \
	fi

.PHONY: check-dependencies
check-dependencies: ## Check required tools are installed
	@printf "$(YELLOW)Checking required dependencies...$(NC)\n"
	@command -v tofu >/dev/null 2>&1 && printf "$(GREEN)✓ tofu found$(NC)\n" || printf "$(RED)✗ tofu not found$(NC)\n"
	@command -v kubectl >/dev/null 2>&1 && printf "$(GREEN)✓ kubectl found$(NC)\n" || printf "$(RED)✗ kubectl not found$(NC)\n"
	@command -v ssh >/dev/null 2>&1 && printf "$(GREEN)✓ ssh found$(NC)\n" || printf "$(RED)✗ ssh not found$(NC)\n"
	@command -v curl >/dev/null 2>&1 && printf "$(GREEN)✓ curl found$(NC)\n" || printf "$(RED)✗ curl not found$(NC)\n"
	@command -v wakeonlan >/dev/null 2>&1 && printf "$(GREEN)✓ wakeonlan found$(NC)\n" || printf "$(YELLOW)! wakeonlan not found (optional, needed for power-on)$(NC)\n"

.PHONY: ssh-%
ssh-%: ## SSH into a specific Proxmox node (e.g. make ssh-pve2)
	@host="$(PROXMOX_HOST_$*)"; \
	if [ -z "$$host" ]; then \
		printf "$(RED)✗ Unknown Proxmox node '$*' (add it to PROXMOX_NODES)$(NC)\n"; \
		exit 1; \
	fi; \
	ssh $(PROXMOX_USER)@$$host

.PHONY: ssh
ssh: ssh-$(PROXMOX_DEFAULT_NODE) ## SSH into the default Proxmox node (see PROXMOX_DEFAULT_NODE)

.PHONY: power-status-%
power-status-%: ## Check if a specific Proxmox node is reachable (e.g. make power-status-pve2)
	@host="$(PROXMOX_HOST_$*)"; \
	if [ -z "$$host" ]; then \
		printf "$(RED)✗ Unknown Proxmox node '$*' (add it to PROXMOX_NODES)$(NC)\n"; \
		exit 1; \
	fi; \
	printf "$(YELLOW)Checking $* ($$host) status...$(NC)\n"; \
	if ping -c 1 -W 2 $$host >/dev/null 2>&1; then \
		printf "$(GREEN)✓ $* is online$(NC)\n"; \
	else \
		printf "$(RED)✗ $* is offline$(NC)\n"; \
		exit 1; \
	fi

.PHONY: power-status
power-status: power-status-$(PROXMOX_DEFAULT_NODE) ## Check if the default Proxmox node is reachable

.PHONY: power-status-all
power-status-all: ## Check reachability of every registered Proxmox node
	@for node in $(PROXMOX_NODES); do $(MAKE) power-status-$$node || true; done

.PHONY: power-on-%
power-on-%: ## Power on a specific Proxmox node via Wake-on-LAN (e.g. make power-on-pve2)
	@host="$(PROXMOX_HOST_$*)"; \
	mac="$(PROXMOX_MAC_$*)"; \
	if [ -z "$$host" ]; then \
		printf "$(RED)✗ Unknown Proxmox node '$*' (add it to PROXMOX_NODES)$(NC)\n"; \
		exit 1; \
	fi; \
	printf "$(YELLOW)Powering on $*...$(NC)\n"; \
	if [ -z "$$mac" ]; then \
		printf "$(RED)✗ PROXMOX_MAC_$* not set$(NC)\n"; \
		printf "$(YELLOW)Usage: make power-on-$* PROXMOX_MAC_$*=xx:xx:xx:xx:xx:xx$(NC)\n"; \
		printf "$(YELLOW)Or set it in .env file$(NC)\n"; \
		exit 1; \
	fi; \
	if ! command -v wakeonlan >/dev/null 2>&1; then \
		printf "$(RED)✗ wakeonlan not installed$(NC)\n"; \
		printf "$(YELLOW)Install with: brew install wakeonlan$(NC)\n"; \
		exit 1; \
	fi; \
	wakeonlan -i $(PROXMOX_BROADCAST) $$mac; \
	printf "$(GREEN)✓ Wake-on-LAN packet sent to $$mac$(NC)\n"; \
	printf "$(YELLOW)Waiting for $* to come online (this may take 30-60 seconds)...$(NC)\n"; \
	i=0; \
	while [ $$i -lt 12 ]; do \
		if ping -c 1 -W 2 $$host >/dev/null 2>&1; then \
			printf "$(GREEN)✓ $* is now online$(NC)\n"; \
			exit 0; \
		fi; \
		printf "."; \
		sleep 5; \
		i=$$((i + 1)); \
	done; \
	printf "\n$(YELLOW)! $* did not respond within 60 seconds$(NC)\n"; \
	printf "$(YELLOW)It may still be booting. Try 'make power-status-$*' in a moment.$(NC)\n"

.PHONY: power-on
power-on: power-on-$(PROXMOX_DEFAULT_NODE) ## Power on the default Proxmox node via Wake-on-LAN

.PHONY: power-off-%
power-off-%: ## Gracefully shut down a specific Proxmox node (e.g. make power-off-pve2)
	@host="$(PROXMOX_HOST_$*)"; \
	if [ -z "$$host" ]; then \
		printf "$(RED)✗ Unknown Proxmox node '$*' (add it to PROXMOX_NODES)$(NC)\n"; \
		exit 1; \
	fi; \
	printf "$(RED)WARNING: This will shut down $* ($$host)$(NC)\n"; \
	read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || (printf "Cancelled\n"; exit 1); \
	printf "$(YELLOW)Shutting down $*...$(NC)\n"; \
	if ssh -o ConnectTimeout=5 $(PROXMOX_USER)@$$host "shutdown -h now" 2>/dev/null; then \
		printf "$(GREEN)✓ Shutdown command sent successfully$(NC)\n"; \
	else \
		printf "$(RED)✗ Failed to send shutdown command$(NC)\n"; \
		printf "$(YELLOW)Make sure SSH access is configured$(NC)\n"; \
		exit 1; \
	fi

.PHONY: power-off
power-off: power-off-$(PROXMOX_DEFAULT_NODE) ## Gracefully shut down the default Proxmox node

.PHONY: proxmox-info-%
proxmox-info-%: ## Get a specific Proxmox node's information via SSH (e.g. make proxmox-info-pve2)
	@host="$(PROXMOX_HOST_$*)"; \
	if [ -z "$$host" ]; then \
		printf "$(RED)✗ Unknown Proxmox node '$*' (add it to PROXMOX_NODES)$(NC)\n"; \
		exit 1; \
	fi; \
	printf "$(YELLOW)Retrieving $* information...$(NC)\n"; \
	ssh $(PROXMOX_USER)@$$host "\
		printf '$(GREEN)System Information:$(NC)\n'; \
		printf 'Hostname: %s\n' \"\$$(hostname)\"; \
		printf 'Proxmox Version: %s\n' \"\$$(pveversion)\"; \
		printf '\n'; \
		printf '$(GREEN)Resources:$(NC)\n'; \
		printf 'Memory: %s total, %s available\n' \"\$$(free -h | grep Mem | awk '{print \$$2}')\", \"\$$(free -h | grep Mem | awk '{print \$$7}')\"; \
		printf 'CPU: %s cores\n' \"\$$(nproc)\"; \
		printf 'Load Average: %s\n' \"\$$(uptime | awk -F'load average:' '{print \$$2}')\"; \
		printf '\n'; \
		printf '$(GREEN)Storage:$(NC)\n'; \
		pvesm status; \
		printf '\n'; \
		printf '$(GREEN)Network Bridges:$(NC)\n'; \
		ip -br link show type bridge; \
	"

.PHONY: proxmox-info
proxmox-info: proxmox-info-$(PROXMOX_DEFAULT_NODE) ## Get the default Proxmox node's information via SSH

.PHONY: list-vms-%
list-vms-%: ## List all VMs on a specific Proxmox node (e.g. make list-vms-pve2)
	@host="$(PROXMOX_HOST_$*)"; \
	if [ -z "$$host" ]; then \
		printf "$(RED)✗ Unknown Proxmox node '$*' (add it to PROXMOX_NODES)$(NC)\n"; \
		exit 1; \
	fi; \
	printf "$(YELLOW)Listing VMs on $*...$(NC)\n"; \
	ssh $(PROXMOX_USER)@$$host "qm list"

.PHONY: list-vms
list-vms: list-vms-$(PROXMOX_DEFAULT_NODE) ## List all VMs on the default Proxmox node

.PHONY: list-templates-%
list-templates-%: ## List all VM templates on a specific Proxmox node (e.g. make list-templates-pve2)
	@host="$(PROXMOX_HOST_$*)"; \
	if [ -z "$$host" ]; then \
		printf "$(RED)✗ Unknown Proxmox node '$*' (add it to PROXMOX_NODES)$(NC)\n"; \
		exit 1; \
	fi; \
	printf "$(YELLOW)Listing VM templates on $*...$(NC)\n"; \
	ssh $(PROXMOX_USER)@$$host "qm list | grep -E '(VMID|template)' || printf 'No templates found\n'"

.PHONY: list-templates
list-templates: list-templates-$(PROXMOX_DEFAULT_NODE) ## List all VM templates on the default Proxmox node

.PHONY: check-cloud-init-template-%
check-cloud-init-template-%: ## Check if the cloud-init template exists on a node (e.g. make check-cloud-init-template-pve2)
	@host="$(PROXMOX_HOST_$*)"; \
	tid="$(PROXMOX_TEMPLATE_ID_$*)"; \
	if [ -z "$$host" ] || [ -z "$$tid" ]; then \
		printf "$(RED)✗ Unknown Proxmox node '$*' (add it to PROXMOX_NODES)$(NC)\n"; \
		exit 1; \
	fi; \
	printf "$(YELLOW)Checking for cloud-init template (VM $$tid) on $*...$(NC)\n"; \
	if ssh $(PROXMOX_USER)@$$host "qm list | grep -q '^[[:space:]]*'$$tid" ; then \
		printf "$(GREEN)✓ Cloud-init template VM $$tid exists on $*$(NC)\n"; \
		ssh $(PROXMOX_USER)@$$host "qm config $$tid | head -20"; \
	else \
		printf "$(YELLOW)! Cloud-init template VM $$tid not found on $*$(NC)\n"; \
		printf "$(YELLOW)Run 'make create-cloud-init-template-$*' to create it$(NC)\n"; \
	fi

.PHONY: check-cloud-init-template
check-cloud-init-template: check-cloud-init-template-$(PROXMOX_DEFAULT_NODE) ## Check if the cloud-init template exists on the default node

.PHONY: create-cloud-init-template-%
create-cloud-init-template-%: ## Create the Ubuntu 22.04 cloud-init template on a node (e.g. make create-cloud-init-template-pve2)
	@host="$(PROXMOX_HOST_$*)"; \
	storage="$(PROXMOX_STORAGE_$*)"; \
	tid="$(PROXMOX_TEMPLATE_ID_$*)"; \
	if [ -z "$$host" ] || [ -z "$$storage" ] || [ -z "$$tid" ]; then \
		printf "$(RED)✗ Unknown Proxmox node '$*' (add it to PROXMOX_NODES)$(NC)\n"; \
		exit 1; \
	fi; \
	printf "$(YELLOW)Creating cloud-init template (VM $$tid) on $* using storage '$$storage'...$(NC)\n"; \
	ssh $(PROXMOX_USER)@$$host "\
		cd /tmp && \
		wget -q https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img && \
		apt-get update && \
		apt-get install -y libguestfs-tools && \
		virt-customize -a jammy-server-cloudimg-amd64.img \
			--install qemu-guest-agent \
			--run-command 'systemctl enable qemu-guest-agent' && \
		qm create $$tid --name ubuntu-cloud --memory 2048 --net0 virtio,bridge=vmbr0 && \
		qm importdisk $$tid jammy-server-cloudimg-amd64.img $$storage && \
		disk=\$$(qm config $$tid | awk -F': ' '/^unused0:/ {print \$$2}') && \
		qm set $$tid --scsihw virtio-scsi-pci --scsi0 \$$disk && \
		qm set $$tid --ide2 $$storage:cloudinit && \
		qm set $$tid --boot c --bootdisk scsi0 && \
		qm set $$tid --serial0 socket --vga serial0 && \
		qm set $$tid --agent enabled=1 && \
		qm template $$tid && \
		rm jammy-server-cloudimg-amd64.img && \
		printf '$(GREEN)✓ Cloud-init template created successfully$(NC)\n' \
	"

.PHONY: create-cloud-init-template
create-cloud-init-template: create-cloud-init-template-$(PROXMOX_DEFAULT_NODE) ## Create the cloud-init template on the default node

.PHONY: get-kubeconfig
get-kubeconfig: ## Fetch kubeconfig from the control plane into the meta-repo root
	@printf "$(YELLOW)Fetching kubeconfig from $(CONTROL_PLANE_IP)...$(NC)\n"
	@ssh $(VM_USER)@$(CONTROL_PLANE_IP) "sudo cat /etc/rancher/k3s/k3s.yaml" \
		| sed "s#https://127.0.0.1:6443#https://$(CONTROL_PLANE_IP):6443#" > $(KUBECONFIG_OUT)
	@chmod 600 $(KUBECONFIG_OUT)
	@printf "$(GREEN)✓ Wrote $(KUBECONFIG_OUT)$(NC)\n"
	@printf "$(YELLOW)direnv exports KUBECONFIG from .envrc — run 'direnv reload' to pick it up$(NC)\n"

.DEFAULT_GOAL := help
