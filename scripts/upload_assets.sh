#!/usr/bin/env bash
set -euo pipefail

# Verify required environment variables are set
if [ -z "${CF_API_TOKEN:-}" ]; then
  echo "Error: CF_API_TOKEN environment variable is required"
  echo "Run: export TF_VAR_cloudflare_api_token=your_token_here"
  exit 1
fi

if [ -z "${CF_ACCOUNT_ID:-}" ]; then
  echo "Error: CF_ACCOUNT_ID environment variable is required" 
  echo "Run: export TF_VAR_cloudflare_account_id=your_account_id_here"
  exit 1
fi

ASSETS_DIR="./dist"
MANIFEST_FILE="./scripts/manifest.json"
TOKEN_FILE="./scripts/assets_token.txt"
SCRIPT_NAME="${WORKER_SCRIPT_NAME:-my-tf-assets}"

# 1. Generate a manifest locally (hash + size).
#    Replace this with logic in the language of your choice.
node ./scripts/generateManifest.js "${ASSETS_DIR}" > "${MANIFEST_FILE}"

# 2. Post the manifest to get the upload token, along with which files need uploading.
UPLOAD_SESSION_RESPONSE=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/workers/scripts/${SCRIPT_NAME}/assets-upload-session" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data @"${MANIFEST_FILE}")

# 3. Extract the JWT and buckets for files that need uploading
UPLOAD_JWT=$(echo "${UPLOAD_SESSION_RESPONSE}" | jq -r '.result.jwt')
BUCKETS=$(echo "${UPLOAD_SESSION_RESPONSE}"   | jq -r '.result.buckets | @base64')

# If no buckets, the JWT might already be a completion token
if [ "$(echo "${UPLOAD_SESSION_RESPONSE}" | jq -r '.result.buckets | length')" -eq 0 ]; then
  # Already have a completion token
  echo "${UPLOAD_JWT}" > "${TOKEN_FILE}"
  echo "All assets are already uploaded. Skipping file uploads."
  exit 0
fi

# 4. Otherwise, upload required files in each bucket.
for bucket_index in $(seq 0 $(($(echo "${UPLOAD_SESSION_RESPONSE}" | jq -r '.result.buckets | length') - 1))); do
  # Decode the list of hashes in this bucket
  HASH_LIST=$(echo "${BUCKETS}" | base64 --decode | jq -r ".[$bucket_index][]")
  
  # Create a temp directory for this bucket's files
  BUCKET_DIR=$(mktemp -d)
  
  # For each hash in the bucket
  for hash in $HASH_LIST; do
    # Find file in manifest that matches this hash
    FILE_PATH=$(cat "${MANIFEST_FILE}" | jq -r "to_entries[] | select(.value.hash | contains(\"${hash}\")) | .key")
    
    if [ -n "$FILE_PATH" ]; then
      # Remove leading slash for file path
      FILE_PATH="${FILE_PATH#/}"
      FILE_SOURCE="${ASSETS_DIR}/${FILE_PATH}"
      
      # Copy file to temp dir
      mkdir -p "$(dirname "${BUCKET_DIR}/${FILE_PATH}")"
      cp "${FILE_SOURCE}" "${BUCKET_DIR}/${FILE_PATH}"
    fi
  done
  
  # Create multipart form data for this bucket
  FORM_DATA="--form jwt=${UPLOAD_JWT}"
  
  # Add each file in this bucket to form data
  find "${BUCKET_DIR}" -type f | while read file; do
    rel_path="${file#$BUCKET_DIR/}"
    FORM_DATA="${FORM_DATA} --form \"${rel_path}=@${file}\""
  done
  
  # Upload the bucket - using correct assets endpoint
  UPLOAD_RESPONSE=$(eval curl -s -X POST \
    "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/workers/scripts/${SCRIPT_NAME}/assets" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: multipart/form-data" \
    ${FORM_DATA})
  
  # Update JWT for next bucket
  UPLOAD_JWT=$(echo "${UPLOAD_RESPONSE}" | jq -r '.result.jwt')
  
  # Clean up temp directory
  rm -rf "${BUCKET_DIR}"
done

# 5. When all uploads complete successfully, the API returns a completion token.
FINAL_JWT="${UPLOAD_JWT}"

# 6. Save the final token to a file so Terraform can read it.
echo "${FINAL_JWT}" > "${TOKEN_FILE}"
echo "All assets uploaded. Completion token saved."
