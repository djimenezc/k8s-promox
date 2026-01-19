# Proxmox K3s Cluster - Makefile
# Verify connections and manage infrastructure

# Proxmox Configuration
PROXMOX_HOST ?= 192.168.50.209
PROXMOX_PORT ?= 8006
PROXMOX_USER ?= root
PROXMOX_API_URL = https://$(PROXMOX_HOST):$(PROXMOX_PORT)/api2/json

# API Token Configuration (override with environment variables or create .env file)
# Format: user@realm!tokenid
PROXMOX_TOKEN_ID ?= root@pam!terraform
PROXMOX_TOKEN_SECRET ?=

# Colors for output
GREEN := \033[0;32m
RED := \033[0;31m
YELLOW := \033[0;33m
NC := \033[0m # No Color

.PHONY: help
help: ## Show this help message
	@echo "Proxmox K3s Cluster - Available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Configuration:"
	@echo "  PROXMOX_HOST: $(PROXMOX_HOST)"
	@echo "  PROXMOX_PORT: $(PROXMOX_PORT)"
	@echo "  PROXMOX_USER: $(PROXMOX_USER)"
	@echo ""

.PHONY: check-all
check-all: check-ssh check-api check-dependencies ## Run all connectivity checks

.PHONY: check-ssh
check-ssh: ## Verify SSH connection to Proxmox host
	@printf "$(YELLOW)Testing SSH connection to $(PROXMOX_HOST)...$(NC)\n"
	@if ssh -o ConnectTimeout=5 -o BatchMode=yes $(PROXMOX_USER)@$(PROXMOX_HOST) "exit" 2>/dev/null; then \
		printf "$(GREEN)✓ SSH connection successful$(NC)\n"; \
	else \
		printf "$(RED)✗ SSH connection failed$(NC)\n"; \
		printf "$(YELLOW)Hint: Run 'ssh-copy-id $(PROXMOX_USER)@$(PROXMOX_HOST)' to set up key-based authentication$(NC)\n"; \
		exit 1; \
	fi

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

.PHONY: ssh
ssh: ## SSH into Proxmox host
	@ssh $(PROXMOX_USER)@$(PROXMOX_HOST)

.PHONY: proxmox-info
proxmox-info: ## Get Proxmox host information via SSH
	@printf "$(YELLOW)Retrieving Proxmox host information...$(NC)\n"
	@ssh $(PROXMOX_USER)@$(PROXMOX_HOST) "\
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

.PHONY: list-vms
list-vms: ## List all VMs on Proxmox
	@printf "$(YELLOW)Listing VMs on Proxmox...$(NC)\n"
	@ssh $(PROXMOX_USER)@$(PROXMOX_HOST) "qm list"

.PHONY: list-templates
list-templates: ## List all VM templates on Proxmox
	@printf "$(YELLOW)Listing VM templates on Proxmox...$(NC)\n"
	@ssh $(PROXMOX_USER)@$(PROXMOX_HOST) "qm list | grep -E '(VMID|template)' || printf 'No templates found\n'"

.PHONY: check-cloud-init-template
check-cloud-init-template: ## Check if cloud-init template (VM 9000) exists
	@printf "$(YELLOW)Checking for cloud-init template (VM 9000)...$(NC)\n"
	@if ssh $(PROXMOX_USER)@$(PROXMOX_HOST) "qm list | grep -q '^[[:space:]]*9000'"; then \
		printf "$(GREEN)✓ Cloud-init template VM 9000 exists$(NC)\n"; \
		ssh $(PROXMOX_USER)@$(PROXMOX_HOST) "qm config 9000 | head -20"; \
	else \
		printf "$(YELLOW)! Cloud-init template VM 9000 not found$(NC)\n"; \
		printf "$(YELLOW)Run 'make create-cloud-init-template' to create it$(NC)\n"; \
	fi

.PHONY: create-cloud-init-template
create-cloud-init-template: ## Create Ubuntu 22.04 cloud-init template
	@printf "$(YELLOW)Creating cloud-init template on Proxmox...$(NC)\n"
	@ssh $(PROXMOX_USER)@$(PROXMOX_HOST) "\
		cd /tmp && \
		wget -q https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img && \
		qm create 9000 --name ubuntu-cloud --memory 2048 --net0 virtio,bridge=vmbr0 && \
		qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm && \
		qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0 && \
		qm set 9000 --ide2 local-lvm:cloudinit && \
		qm set 9000 --boot c --bootdisk scsi0 && \
		qm set 9000 --serial0 socket --vga serial0 && \
		qm set 9000 --agent enabled=1 && \
		qm template 9000 && \
		rm jammy-server-cloudimg-amd64.img && \
		printf '$(GREEN)✓ Cloud-init template created successfully$(NC)\n' \
	"

.PHONY: tofu-init
tofu-init: ## Initialize OpenTofu
	@printf "$(YELLOW)Initializing OpenTofu...$(NC)\n"
	@cd terraform && tofu init

.PHONY: tofu-plan
tofu-plan: ## Run OpenTofu plan
	@printf "$(YELLOW)Running OpenTofu plan...$(NC)\n"
	@cd terraform && tofu plan

.PHONY: tofu-apply
tofu-apply: ## Apply OpenTofu configuration
	@printf "$(YELLOW)Applying OpenTofu configuration...$(NC)\n"
	@cd terraform && tofu apply

.PHONY: tofu-destroy
tofu-destroy: ## Destroy OpenTofu-managed infrastructure
	@printf "$(RED)WARNING: This will destroy all OpenTofu-managed VMs$(NC)\n"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] && \
		cd terraform && tofu destroy || printf "Cancelled\n"

.PHONY: clean
clean: ## Clean temporary files
	@printf "$(YELLOW)Cleaning temporary files...$(NC)\n"
	@rm -rf terraform/.terraform
	@rm -f terraform/.terraform.lock.hcl
	@rm -f terraform/terraform.tfstate.backup
	@printf "$(GREEN)✓ Cleaned$(NC)\n"

.DEFAULT_GOAL := help
