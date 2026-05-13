"""
Bookstore MCP skill.

Environment variables:
  MCP_API_ENDPOINT   Full base URL of the Catalog API Gateway endpoint
                     e.g. http://f71901c1.execute-api.localhost.localstack.cloud:4566
  ORDER_SERVICE_URL  Base URL of the Order service
                     e.g. http://localhost:5001
"""

import asyncio
import os
from typing import Any

import httpx
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool

API_ENDPOINT = os.environ.get(
    "MCP_API_ENDPOINT",
    "http://localhost:4566",   # overridden at runtime via .mcp.json or env
)
ORDER_SERVICE_URL = os.environ.get("ORDER_SERVICE_URL", "http://localhost:5001")

app = Server("bookstore-mcp")


# ── Tool registry ─────────────────────────────────────────────────────────────

@app.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="get_catalog",
            description=(
                "List books available in the bookstore catalog. "
                "Optionally filter by genre to narrow results."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "genre": {
                        "type": "string",
                        "description": "Filter by genre, e.g. Fiction, Technology (optional)",
                    }
                },
            },
        ),
        Tool(
            name="place_order",
            description="Place a new book order on behalf of a customer.",
            inputSchema={
                "type": "object",
                "required": ["userId", "items"],
                "properties": {
                    "userId": {
                        "type": "string",
                        "description": "Customer user ID",
                    },
                    "items": {
                        "type": "array",
                        "description": "Books to order",
                        "items": {
                            "type": "object",
                            "required": ["bookId", "quantity", "price"],
                            "properties": {
                                "bookId":   {"type": "string"},
                                "title":    {"type": "string"},
                                "quantity": {"type": "integer", "minimum": 1},
                                "price":    {"type": "number",  "minimum": 0},
                            },
                        },
                    },
                },
            },
        ),
        Tool(
            name="check_order_status",
            description="Look up the current status and details of an existing order.",
            inputSchema={
                "type": "object",
                "required": ["orderId"],
                "properties": {
                    "orderId": {
                        "type": "string",
                        "description": "The order ID returned by place_order",
                    }
                },
            },
        ),
    ]


# ── Tool dispatcher ───────────────────────────────────────────────────────────

@app.call_tool()
async def call_tool(name: str, arguments: dict[str, Any]) -> list[TextContent]:
    handlers = {
        "get_catalog":        _get_catalog,
        "place_order":        _place_order,
        "check_order_status": _check_order_status,
    }
    if name not in handlers:
        raise ValueError(f"Unknown tool: {name!r}")
    return await handlers[name](arguments)


# ── Tool implementations ──────────────────────────────────────────────────────

async def _get_catalog(args: dict) -> list[TextContent]:
    params = {}
    if genre := args.get("genre"):
        params["genre"] = genre

    async with httpx.AsyncClient() as client:
        r = await client.get(f"{API_ENDPOINT}/books", params=params, timeout=10)
        r.raise_for_status()
        books = r.json()

    if not books:
        suffix = f" in genre '{params['genre']}'" if params.get("genre") else ""
        return [TextContent(type="text", text=f"No books found{suffix}.")]

    lines = [f"Found {len(books)} book(s):\n"]
    for b in books:
        lines.append(
            f"  [{b['bookId']}] {b['title']} by {b['author']}"
            f" | {b['genre']} | ${float(b['price']):.2f} | stock: {b.get('stock', 0)}"
        )
    return [TextContent(type="text", text="\n".join(lines))]


async def _place_order(args: dict) -> list[TextContent]:
    payload = {"userId": args["userId"], "items": args["items"]}
    async with httpx.AsyncClient() as client:
        r = await client.post(
            f"{ORDER_SERVICE_URL}/orders", json=payload, timeout=10
        )
        r.raise_for_status()
        order = r.json()

    item_titles = ", ".join(
        i.get("title", i["bookId"]) for i in order["items"]
    )
    return [TextContent(
        type="text",
        text=(
            f"Order placed!\n"
            f"  Order ID : {order['orderId']}\n"
            f"  Status   : {order['status']}\n"
            f"  Items    : {item_titles}\n"
            f"  Total    : ${float(order['totalAmount']):.2f}"
        ),
    )]


async def _check_order_status(args: dict) -> list[TextContent]:
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{ORDER_SERVICE_URL}/orders/{args['orderId']}", timeout=10
        )
        if r.status_code == 404:
            return [TextContent(
                type="text",
                text=f"Order {args['orderId']!r} not found.",
            )]
        r.raise_for_status()
        order = r.json()

    return [TextContent(
        type="text",
        text=(
            f"Order {order['orderId']}\n"
            f"  Status  : {order['status']}\n"
            f"  User    : {order['userId']}\n"
            f"  Total   : ${float(order['totalAmount']):.2f}\n"
            f"  Placed  : {order['createdAt']}\n"
            f"  Updated : {order['updatedAt']}"
        ),
    )]


# ── Entry point ───────────────────────────────────────────────────────────────

async def main():
    async with stdio_server() as (read, write):
        await app.run(read, write, app.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(main())
