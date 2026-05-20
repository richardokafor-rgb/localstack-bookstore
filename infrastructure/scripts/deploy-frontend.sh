#!/usr/bin/env bash
# Builds the React app and syncs dist/ to the LocalStack S3 bucket.
# Reads the API endpoint and bucket name from Terraform outputs so it works
# after both `tflocal apply` and `localstack pod load`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infrastructure/terraform"
FRONTEND_DIR="$REPO_ROOT/frontend"

API_ENDPOINT=$(cd "$TF_DIR" && tflocal output -raw api_endpoint 2>/dev/null)
if [[ -z "$API_ENDPOINT" ]]; then
  echo "ERROR: could not read api_endpoint from tflocal output — did tflocal apply succeed?" >&2
  exit 1
fi

BUCKET=$(cd "$TF_DIR" && tflocal output -raw frontend_bucket 2>/dev/null)
if [[ -z "$BUCKET" ]]; then
  echo "ERROR: could not read frontend_bucket from tflocal output" >&2
  exit 1
fi

# Write .env.local so the dev server also picks up the current endpoint
cat > "$FRONTEND_DIR/.env.local" <<ENVEOF
VITE_API_ENDPOINT=$API_ENDPOINT
VITE_ORDER_SERVICE_URL=http://localhost:5001
ENVEOF
echo "Updated frontend/.env.local → VITE_API_ENDPOINT=$API_ENDPOINT"

# Build
cd "$FRONTEND_DIR"
npm install --silent
VITE_API_ENDPOINT="$API_ENDPOINT" VITE_ORDER_SERVICE_URL="http://localhost:5001" npm run build

# Sync to S3 — hashed assets get long-lived cache; index.html gets no-cache
awslocal s3 sync dist/ "s3://$BUCKET/" --delete
awslocal s3 cp dist/index.html "s3://$BUCKET/index.html" \
  --content-type text/html --cache-control "no-cache, no-store"

CF_DOMAIN=$(cd "$TF_DIR" && tflocal output -raw cloudfront_domain 2>/dev/null || true)
if [[ -n "$CF_DOMAIN" ]]; then
  echo "Frontend deployed → http://$CF_DOMAIN"
else
  echo "Frontend deployed → s3://$BUCKET"
fi
