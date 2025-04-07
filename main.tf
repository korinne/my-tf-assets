# https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/workers_script

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.2.0"
    }
  }
}

provider "cloudflare" {
  # Use environment variable instead of hardcoded token
  # export TF_VAR_cloudflare_api_token=your_token_here
  api_token = var.cloudflare_api_token
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "worker_script_name" {
  description = "Name of the Cloudflare Worker script"
  type        = string
  default     = "my-tf-assets"
}

resource "null_resource" "upload_assets" {
  provisioner "local-exec" {
    command = "bash ./scripts/upload_assets.sh"
    
    # Pass the environment variables directly to the script
    environment = {
      CF_API_TOKEN = var.cloudflare_api_token
      CF_ACCOUNT_ID = var.cloudflare_account_id
      WORKER_SCRIPT_NAME = var.worker_script_name
    }
  }
}

resource "cloudflare_workers_script" "terraformed_assets" {
  account_id   = var.cloudflare_account_id
  script_name  = var.worker_script_name
  content = file("${path.module}/worker/index.ts")
  main_module = "index.ts"
  compatibility_date = "2025-04-01"

  # Use JWT approach for assets with binding
  assets = {
    config = {
      not_found_handling = "single-page-application"
    }
    jwt = file("${path.module}/scripts/assets_token.txt")
  }
  
  # Add binding for assets
  bindings = [
    {
      name = "ASSETS"
      type = "assets"
    }
  ]
  
  # Add dependency on the upload_assets resource
  depends_on = [null_resource.upload_assets]
}