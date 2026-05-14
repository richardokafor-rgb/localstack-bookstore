#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/../terraform"
API_ENDPOINT=$(cd "$TF_DIR" && tflocal output -raw api_endpoint 2>/dev/null || echo "http://localhost:4566")

echo "==> Clearing existing items from local-books table…"
items=$(awslocal dynamodb scan \
  --table-name local-books \
  --projection-expression "bookId" \
  --query "Items[].bookId.S" \
  --output text 2>/dev/null || true)
for book_id in $items; do
  awslocal dynamodb delete-item \
    --table-name local-books \
    --key "{\"bookId\":{\"S\":\"$book_id\"}}" 2>/dev/null || true
done
echo "   cleared."

echo "==> Seeding books via $API_ENDPOINT/books"

books=(
  '{"title":"The Pragmatic Programmer","author":"David Thomas","genre":"Technology","price":39.99,"stock":25}'
  '{"title":"Clean Code","author":"Robert C. Martin","genre":"Technology","price":34.99,"stock":18}'
  '{"title":"Designing Data-Intensive Applications","author":"Martin Kleppmann","genre":"Technology","price":49.99,"stock":12}'
  '{"title":"The Hitchhiker'\''s Guide to the Galaxy","author":"Douglas Adams","genre":"Fiction","price":14.99,"stock":30}'
  '{"title":"Dune","author":"Frank Herbert","genre":"Fiction","price":17.99,"stock":22}'
  '{"title":"Sapiens","author":"Yuval Noah Harari","genre":"Non-Fiction","price":19.99,"stock":15}'
)

for book in "${books[@]}"; do
  title=$(echo "$book" | python3 -c "import sys,json; print(json.load(sys.stdin)['title'])")
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$API_ENDPOINT/books" \
    -H "Content-Type: application/json" \
    -d "$book")
  echo "   $title → HTTP $status"
done

echo ""
echo "✓ Seed complete. Run: curl -s $API_ENDPOINT/books | python3 -m json.tool"
