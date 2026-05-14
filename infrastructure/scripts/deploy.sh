#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infrastructure/terraform"
ENVIRONMENT="${1:-local}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
LS_ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"

echo "==> Deploying localstack-bookstore (env: $ENVIRONMENT)"

# ── 1. Build Lambda ─────────────────────────────────────────────────────────
echo "==> Building catalog-api Lambda…"
(cd "$REPO_ROOT/services/catalog-api" && npm install --production --silent)

# ── 2. Terraform apply ───────────────────────────────────────────────────────
echo "==> Running tflocal apply…"
(cd "$TF_DIR" && tflocal init -upgrade -input=false && \
  tflocal apply -auto-approve -var="environment=$ENVIRONMENT")

# ── 3. Capture outputs ────────────────────────────────────────────────────────
API_ENDPOINT=$(cd "$TF_DIR" && tflocal output -raw api_endpoint)
ECR_URL=$(cd "$TF_DIR" && tflocal output -raw ecr_repository_url)
FRONTEND_BUCKET=$(cd "$TF_DIR" && tflocal output -raw frontend_bucket)

echo "   API endpoint : $API_ENDPOINT"
echo "   ECR URL      : $ECR_URL"
echo "   S3 bucket    : $FRONTEND_BUCKET"

# ── 4. Build & push order-service Docker image ───────────────────────────────
echo "==> Building order-service Docker image…"
(cd "$REPO_ROOT/services/order-service" && \
  docker build -t "$ECR_URL:latest" .)

echo "==> Pushing to ECR (LocalStack)…"
awslocal ecr get-login-password | \
  docker login --username AWS --password-stdin 000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4566
docker push "$ECR_URL:latest"

# ── 5. Re-apply Terraform to wire in the new image ───────────────────────────
echo "==> Re-applying Terraform with container image…"
(cd "$TF_DIR" && tflocal apply -auto-approve \
  -var="environment=$ENVIRONMENT" \
  -var="order_service_image=$ECR_URL:latest")

# ── 6. Build & deploy frontend to S3 ─────────────────────────────────────────
echo "==> Building React frontend…"
(cd "$REPO_ROOT/frontend" && \
  VITE_API_ENDPOINT="$API_ENDPOINT" npm run build)

echo "==> Syncing frontend to S3…"
awslocal s3 sync "$REPO_ROOT/frontend/dist/" "s3://$FRONTEND_BUCKET/" \
  --delete --content-type "text/html"

echo ""
echo "✓ Deployment complete!"
echo "  Catalog API : $API_ENDPOINT/books"
echo "  Frontend    : http://$FRONTEND_BUCKET.s3-website-$REGION.amazonaws.com"
