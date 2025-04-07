# Terraforming assets

The current path for uploading assets to Cloudflare Workers via Terraform.

## Setup

1. Clone this repository

2. Set Terraform variables directly in your shell:

   ```bash
   # Set Terraform variables directly
   export TF_VAR_cloudflare_api_token="your_api_token_here"
   export TF_VAR_cloudflare_account_id="your_account_id_here"
   export TF_VAR_worker_script_name="my-tf-assets"  # Optional, defaults to "my-tf-assets"
   ```

   These variables will be automatically used by Terraform and passed to the upload script.

## Deploying

Follow these steps to deploy your Worker with assets:

1. Build your assets:

   ```bash
   npm run build
   ```

2. Generate an asset token by running the upload script:

   ```bash
   # Export required environment variables (these must match your TF_VAR variables)
   export CF_API_TOKEN=$TF_VAR_cloudflare_api_token
   export CF_ACCOUNT_ID=$TF_VAR_cloudflare_account_id
   export WORKER_SCRIPT_NAME=$TF_VAR_worker_script_name  # Optional

   # Run the upload script
   bash ./scripts/upload_assets.sh
   ```

3. Apply Terraform configuration

   ```bash
   # Make sure TF_VAR environment variables are set
   export TF_VAR_cloudflare_api_token="your_api_token_here"
   export TF_VAR_cloudflare_account_id="your_account_id_here"
   export TF_VAR_worker_script_name="my-tf-assets"  # Optional

   # Apply configuration
   terraform apply
   ```

### Important Notes About Asset Deployment

- The JWT token in `scripts/assets_token.txt` can only be used once. If you get a "token already consumed" error, you need to regenerate it by running the upload script again.

- Always run the upload script before `terraform apply` to ensure a valid token exists.

- If you make changes to your frontend assets, you must:

  1. Rebuild the assets
  2. Regenerate the token by running the upload script
  3. Run terraform apply again

- The order of operations is important:
  1. Build → 2. Upload → 3. Apply

### Potential Terraform Provider Bug

**Bug Description:** The Cloudflare Terraform provider (v5.2.0) automatically adds both `run_worker_first = false` and `serve_directly = true` to the assets configuration, even when neither is specified in your Terraform configuration. This causes a Cloudflare API error because these flags are mutually exclusive.

**Error Message:**

```
"errors": [
  {
    "code": 10021,
    "message": "serve_directly and run_worker_first must not be simultaneously specified"
  }
]
```

**How to Reproduce:**

1. Use the `cloudflare_workers_script` resource with an assets block
2. Define minimal assets configuration (without specifying either flag):
   ```terraform
   assets = {
     config = {
       not_found_handling = "single-page-application"
     }
     jwt = file("${path.module}/scripts/assets_token.txt")
   }
   ```
3. Run `terraform apply`
4. The provider will add both flags to the API request, resulting in an error

**Affected Versions:** Cloudflare provider v5.2.0
