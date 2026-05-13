import os
import uuid

import boto3
import pytest
import requests

ENDPOINT = os.getenv("AWS_ENDPOINT_URL", "http://localhost:4566")
REGION = os.getenv("AWS_DEFAULT_REGION", "us-east-1")
BOOKS_TABLE = os.getenv("BOOKS_TABLE", "local-books")
ORDERS_TABLE = os.getenv("ORDERS_TABLE", "local-orders")

boto_kwargs = {
    "endpoint_url": ENDPOINT,
    "region_name": REGION,
    "aws_access_key_id": "test",
    "aws_secret_access_key": "test",
}


@pytest.fixture(scope="session")
def dynamodb():
    return boto3.resource("dynamodb", **boto_kwargs)


@pytest.fixture(scope="session")
def sqs_client():
    return boto3.client("sqs", **boto_kwargs)


@pytest.fixture(scope="session")
def sns_client():
    return boto3.client("sns", **boto_kwargs)


@pytest.fixture(scope="session")
def apigw_client():
    return boto3.client("apigatewayv2", **boto_kwargs)


@pytest.fixture(scope="session")
def api_endpoint(apigw_client):
    """Resolve the HTTP API endpoint from API Gateway."""
    apis = apigw_client.get_apis()["Items"]
    api = next((a for a in apis if "bookstore-catalog" in a["Name"]), None)
    assert api, "Catalog API not found — did tflocal apply succeed?"
    api_id = api["ApiId"]
    # LocalStack HTTP API v2 uses the execute-api subdomain, not localhost:4566/{id}
    return f"http://{api_id}.execute-api.localhost.localstack.cloud:4566"


@pytest.fixture
def sample_book():
    return {
        "title": f"Test Book {uuid.uuid4().hex[:6]}",
        "author": "Test Author",
        "genre": "Fiction",
        "price": 12.99,
        "stock": 10,
    }


@pytest.fixture(scope="session")
def sample_user_id():
    return f"user-{uuid.uuid4().hex[:8]}"
