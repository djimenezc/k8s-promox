terraform {
  required_version = ">= 1.10.0"

  # Partial config — bucket/key/endpoint/locking are supplied by `make tofu-init`
  # (see the meta-repo's Makefile.tofu). Cloudflare R2 speaks the S3 API.
  backend "s3" {}

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# No provider block: this stack is OS-level package/service config on the
# Proxmox host itself (applied over SSH via null_resource/local-exec), not a
# Proxmox API object — so it has no business going through the bpg/proxmox
# provider's VM-oriented resources.
