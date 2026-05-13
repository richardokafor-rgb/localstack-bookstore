"""Integration tests for the Catalog API (API Gateway + Lambda + DynamoDB)."""
import pytest
import requests


def test_api_is_reachable(api_endpoint):
    r = requests.get(f"{api_endpoint}/books", timeout=10)
    assert r.status_code == 200
    assert isinstance(r.json(), list)


def test_create_book(api_endpoint, sample_book):
    r = requests.post(f"{api_endpoint}/books", json=sample_book, timeout=10)
    assert r.status_code == 201
    data = r.json()
    assert "bookId" in data
    assert data["title"] == sample_book["title"]
    assert data["genre"] == sample_book["genre"]
    return data


def test_get_book(api_endpoint, sample_book):
    created = requests.post(f"{api_endpoint}/books", json=sample_book, timeout=10).json()
    book_id = created["bookId"]

    r = requests.get(f"{api_endpoint}/books/{book_id}", timeout=10)
    assert r.status_code == 200
    assert r.json()["bookId"] == book_id


def test_list_books_by_genre(api_endpoint, sample_book):
    requests.post(f"{api_endpoint}/books", json=sample_book, timeout=10)

    r = requests.get(f"{api_endpoint}/books", params={"genre": sample_book["genre"]}, timeout=10)
    assert r.status_code == 200
    books = r.json()
    assert any(b["genre"] == sample_book["genre"] for b in books)


def test_update_book(api_endpoint, sample_book):
    created = requests.post(f"{api_endpoint}/books", json=sample_book, timeout=10).json()
    book_id = created["bookId"]

    r = requests.put(
        f"{api_endpoint}/books/{book_id}",
        json={"price": 19.99, "stock": 5},
        timeout=10,
    )
    assert r.status_code == 200
    updated = r.json()
    assert float(updated["price"]) == 19.99
    assert int(updated["stock"]) == 5


def test_delete_book(api_endpoint, sample_book):
    created = requests.post(f"{api_endpoint}/books", json=sample_book, timeout=10).json()
    book_id = created["bookId"]

    r = requests.delete(f"{api_endpoint}/books/{book_id}", timeout=10)
    assert r.status_code == 204

    r = requests.get(f"{api_endpoint}/books/{book_id}", timeout=10)
    assert r.status_code == 404


def test_get_nonexistent_book(api_endpoint):
    r = requests.get(f"{api_endpoint}/books/nonexistent-id", timeout=10)
    assert r.status_code == 404


def test_create_book_missing_fields(api_endpoint):
    r = requests.post(f"{api_endpoint}/books", json={"title": "No Author"}, timeout=10)
    assert r.status_code == 400
