#!/usr/bin/env bash
# Rewrites .mcp.json with the current API Gateway endpoint from Terraform outputs.
# Run this after every LocalStack restart + tflocal apply.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infrastructure/terraform"
MCP_JSON="$REPO_ROOT/.mcp.json"

API_ENDPOINT=$(cd "$TF_DIR" && tflocal output -raw api_endpoint 2>/dev/null)
if [[ -z "$API_ENDPOINT" ]]; then
  echo "ERROR: could not read api_endpoint from tflocal output — did tflocal apply succeed?" >&2
  exit 1
fi

python3 - "$MCP_JSON" "$API_ENDPOINT" <<'EOF'
import json, sys
path, endpoint = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)
cfg["mcpServers"]["bookstore"]["env"]["MCP_API_ENDPOINT"] = endpoint
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
EOF

echo "Updated .mcp.json → MCP_API_ENDPOINT=$API_ENDPOINT"

# Write frontend/.env.local so `npm run dev` picks up the endpoint automatically
ENV_LOCAL="$REPO_ROOT/frontend/.env.local"
cat > "$ENV_LOCAL" <<ENVEOF
VITE_API_ENDPOINT=$API_ENDPOINT
VITE_ORDER_SERVICE_URL=http://localhost:5001
ENVEOF
echo "Updated frontend/.env.local → VITE_API_ENDPOINT=$API_ENDPOINT"
