terraform {
  required_version = ">= 1.10.0"

  # Partial config — bucket/key/endpoint/locking are supplied by `make tofu-init`
  # (see the meta-repo's Makefile.tofu). Cloudflare R2 speaks the S3 API.
  backend "s3" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.78"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true
}
