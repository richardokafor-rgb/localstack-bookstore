#!/usr/bin/env bash
# Starts the Flask order service locally on port 5001 with env vars from Terraform outputs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TF_DIR="$REPO_ROOT/infrastructure/terraform"
SERVICE_DIR="$REPO_ROOT/services/order-service"
LOG_FILE="/tmp/order-service.log"
PID_FILE="/tmp/order-service.pid"

# Kill any existing instance
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Stopping existing order service (PID $OLD_PID)..."
    kill "$OLD_PID"
  fi
  rm -f "$PID_FILE"
fi

# Read env vars from Terraform outputs
ORDERS_TABLE=$(cd "$TF_DIR" && tflocal output -raw orders_table 2>/dev/null)
USERS_TABLE=$(cd "$TF_DIR" && tflocal output -raw users_table 2>/dev/null) || \
  USERS_TABLE="${ORDERS_TABLE/orders/users}"
ORDER_QUEUE_URL=$(cd "$TF_DIR" && tflocal output -raw order_queue_url 2>/dev/null)
NOTIFICATIONS_TOPIC_ARN=$(cd "$TF_DIR" && tflocal output -raw notifications_topic_arn 2>/dev/null)

if [[ -z "$ORDERS_TABLE" ]]; then
  echo "ERROR: could not read orders_table from tflocal output — did tflocal apply succeed?" >&2
  exit 1
fi

# Create venv and install deps if needed
cd "$SERVICE_DIR"
VENV="$SERVICE_DIR/.venv"
[[ -d "$VENV" ]] || python3 -m venv "$VENV"
"$VENV/bin/pip" install -q -r requirements.txt

# Start Flask in the background
ORDERS_TABLE="$ORDERS_TABLE" \
USERS_TABLE="$USERS_TABLE" \
ORDER_QUEUE_URL="$ORDER_QUEUE_URL" \
NOTIFICATIONS_TOPIC_ARN="$NOTIFICATIONS_TOPIC_ARN" \
AWS_ENDPOINT_URL="http://localhost:4566" \
AWS_DEFAULT_REGION="us-east-1" \
AWS_ACCESS_KEY_ID="test" \
AWS_SECRET_ACCESS_KEY="test" \
"$VENV/bin/python" run.py >"$LOG_FILE" 2>&1 &

echo $! >"$PID_FILE"
echo "Order service started on :5001 (PID $(cat "$PID_FILE")) → $LOG_FILE"
