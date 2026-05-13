"""
End-to-end tests for the bookstore MCP skill.

Calls _get_catalog, _place_order, and _check_order_status directly
(bypassing stdio transport) against live LocalStack infrastructure and
a locally-started instance of the Flask order service.
"""

import asyncio
import os
import subprocess
import sys
import time

import pytest
import requests

# ── resolve the API endpoint dynamically so tests survive LocalStack restarts ─
def _resolve_api_endpoint() -> str:
    """Look up the live API GW endpoint by name rather than hardcoding the ID."""
    import boto3
    endpoint = os.environ.get("AWS_ENDPOINT_URL", "http://localhost:4566")
    client = boto3.client(
        "apigatewayv2",
        endpoint_url=endpoint,
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
        aws_access_key_id="test",
        aws_secret_access_key="test",
    )
    apis = client.get_apis()["Items"]
    api = next((a for a in apis if "bookstore-catalog" in a["Name"]), None)
    assert api, "Catalog API not found — run tflocal apply first"
    return f"http://{api['ApiId']}.execute-api.localhost.localstack.cloud:4566"


API_ENDPOINT = _resolve_api_endpoint()
ORDER_SERVICE_URL = "http://localhost:5001"

os.environ["MCP_API_ENDPOINT"] = API_ENDPOINT
os.environ["ORDER_SERVICE_URL"] = ORDER_SERVICE_URL
os.environ.setdefault("AWS_ENDPOINT_URL", "http://localhost:4566")
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "test")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "test")

sys.path.insert(
    0,
    os.path.join(os.path.dirname(__file__), "../../services/mcp-skill"),
)
from server import _check_order_status, _get_catalog, _place_order, list_tools


# ── fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def order_service():
    """Start the Flask order service on port 5000 for the duration of this module."""
    svc_dir = os.path.join(os.path.dirname(__file__), "../../services/order-service")
    env = {
        **os.environ,
        "ORDERS_TABLE": "local-orders",
        "USERS_TABLE": "local-users",
        "ORDER_QUEUE_URL": (
            "http://sqs.us-east-1.localhost.localstack.cloud:4566"
            "/000000000000/local-order-queue"
        ),
        "NOTIFICATIONS_TOPIC_ARN": (
            "arn:aws:sns:us-east-1:000000000000:local-order-notifications"
        ),
        "AWS_ENDPOINT_URL": "http://localhost:4566",
        "AWS_DEFAULT_REGION": "us-east-1",
        "AWS_ACCESS_KEY_ID": "test",
        "AWS_SECRET_ACCESS_KEY": "test",
    }
    proc = subprocess.Popen(
        [sys.executable, "run.py"],
        cwd=os.path.abspath(svc_dir),
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # Wait up to 10 s for the health endpoint to respond
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            if requests.get(f"{ORDER_SERVICE_URL}/health", timeout=1).status_code == 200:
                break
        except requests.exceptions.ConnectionError:
            time.sleep(0.3)
    else:
        proc.terminate()
        pytest.fail("Order service did not start within 10 seconds")

    yield

    proc.terminate()
    proc.wait(timeout=5)


@pytest.fixture(scope="module")
def seeded_book():
    """Create one book in the catalog and return it for use across tests."""
    r = requests.post(
        f"{API_ENDPOINT}/books",
        json={
            "title": "The Pragmatic Programmer",
            "author": "David Thomas",
            "genre": "Technology",
            "price": 39.99,
            "stock": 10,
        },
        timeout=10,
    )
    assert r.status_code == 201, f"Seed failed: {r.status_code} {r.text}"
    return r.json()


# ── tests ─────────────────────────────────────────────────────────────────────

class TestToolRegistry:
    def test_three_tools_registered(self):
        tools = asyncio.run(list_tools())
        names = {t.name for t in tools}
        assert names == {"get_catalog", "place_order", "check_order_status"}

    def test_tool_schemas_have_required_fields(self):
        tools = {t.name: t for t in asyncio.run(list_tools())}

        assert tools["place_order"].inputSchema["required"] == ["userId", "items"]
        assert "orderId" in tools["check_order_status"].inputSchema["required"]
        # get_catalog has no required fields
        assert "required" not in tools["get_catalog"].inputSchema


class TestGetCatalog:
    def test_returns_text_content(self, seeded_book):
        result = asyncio.run(_get_catalog({}))
        assert len(result) == 1
        assert result[0].type == "text"

    def test_lists_seeded_book(self, seeded_book):
        result = asyncio.run(_get_catalog({}))
        text = result[0].text
        assert seeded_book["title"] in text
        assert seeded_book["author"] in text

    def test_filter_by_genre_match(self, seeded_book):
        result = asyncio.run(_get_catalog({"genre": "Technology"}))
        assert seeded_book["title"] in result[0].text

    def test_filter_by_genre_no_match(self, seeded_book):
        result = asyncio.run(_get_catalog({"genre": "Romance"}))
        assert "No books found" in result[0].text

    def test_price_formatted(self, seeded_book):
        result = asyncio.run(_get_catalog({}))
        assert "$39.99" in result[0].text


class TestPlaceOrder:
    def test_place_order_success(self, order_service, seeded_book):
        result = asyncio.run(
            _place_order({
                "userId": "test-user-mcp",
                "items": [{
                    "bookId": seeded_book["bookId"],
                    "title": seeded_book["title"],
                    "quantity": 2,
                    "price": seeded_book["price"],
                }],
            })
        )
        assert len(result) == 1
        text = result[0].text
        assert "Order placed!" in text
        assert "Order ID" in text
        assert "PENDING" in text
        assert "$79.98" in text

    def test_place_order_returns_order_id(self, order_service, seeded_book):
        result = asyncio.run(
            _place_order({
                "userId": "test-user-mcp-2",
                "items": [{
                    "bookId": seeded_book["bookId"],
                    "title": seeded_book["title"],
                    "quantity": 1,
                    "price": 39.99,
                }],
            })
        )
        text = result[0].text
        # Extract order ID from output and verify it looks like a UUID
        import re
        match = re.search(r"Order ID\s*:\s*([a-f0-9-]{36})", text)
        assert match, f"No UUID-shaped order ID found in:\n{text}"


class TestCheckOrderStatus:
    @pytest.fixture(scope="class")
    def placed_order_id(self, order_service, seeded_book):
        result = asyncio.run(
            _place_order({
                "userId": "test-user-status-check",
                "items": [{
                    "bookId": seeded_book["bookId"],
                    "title": seeded_book["title"],
                    "quantity": 1,
                    "price": 39.99,
                }],
            })
        )
        import re
        match = re.search(r"Order ID\s*:\s*([a-f0-9-]{36})", result[0].text)
        assert match
        return match.group(1)

    def test_check_existing_order(self, order_service, placed_order_id):
        result = asyncio.run(_check_order_status({"orderId": placed_order_id}))
        text = result[0].text
        assert placed_order_id in text
        assert "PENDING" in text
        assert "test-user-status-check" in text

    def test_check_nonexistent_order(self, order_service):
        result = asyncio.run(_check_order_status({"orderId": "no-such-order"}))
        assert "not found" in result[0].text.lower()
