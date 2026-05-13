import React, { useEffect, useState } from "react";
import { catalog, orders } from "./api/client.js";

const styles = {
  app: { fontFamily: "system-ui, sans-serif", maxWidth: 960, margin: "0 auto", padding: "1rem" },
  header: { borderBottom: "2px solid #333", paddingBottom: "0.5rem", marginBottom: "1rem" },
  grid: { display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))", gap: "1rem" },
  card: { border: "1px solid #ddd", borderRadius: 8, padding: "1rem", background: "#fafafa" },
  btn: { padding: "0.4rem 0.8rem", borderRadius: 4, border: "none", cursor: "pointer", marginRight: 4 },
  error: { color: "crimson", margin: "0.5rem 0" },
};

function BookCard({ book, onOrder }) {
  return (
    <div style={styles.card}>
      <strong>{book.title}</strong>
      <div style={{ color: "#555", fontSize: 13 }}>{book.author}</div>
      <div style={{ fontSize: 12, marginTop: 4 }}>
        {book.genre} · ${Number(book.price).toFixed(2)} · stock: {book.stock ?? 0}
      </div>
      <button style={{ ...styles.btn, background: "#0070f3", color: "#fff", marginTop: 8 }}
        onClick={() => onOrder(book)}>
        Order
      </button>
    </div>
  );
}

export default function App() {
  const [books, setBooks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [tab, setTab] = useState("catalog");
  const [orderResult, setOrderResult] = useState(null);
  const [userId] = useState(`user-${Math.random().toString(36).slice(2, 8)}`);

  useEffect(() => {
    catalog.list()
      .then(setBooks)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  async function handleOrder(book) {
    try {
      const order = await orders.place({
        userId,
        items: [{ bookId: book.bookId, title: book.title, quantity: 1, price: book.price }],
      });
      setOrderResult(order);
      setTab("orders");
    } catch (e) {
      setError(e.message);
    }
  }

  return (
    <div style={styles.app}>
      <header style={styles.header}>
        <h1 style={{ margin: 0 }}>📚 LocalStack Bookstore</h1>
        <div style={{ marginTop: 8 }}>
          {["catalog", "orders"].map((t) => (
            <button key={t} style={{ ...styles.btn, background: tab === t ? "#333" : "#eee", color: tab === t ? "#fff" : "#333" }}
              onClick={() => setTab(t)}>
              {t.charAt(0).toUpperCase() + t.slice(1)}
            </button>
          ))}
        </div>
      </header>

      {error && <p style={styles.error}>{error}</p>}

      {tab === "catalog" && (
        <>
          <h2>Books ({books.length})</h2>
          {loading ? <p>Loading…</p> : (
            <div style={styles.grid}>
              {books.map((b) => <BookCard key={b.bookId} book={b} onOrder={handleOrder} />)}
              {!books.length && <p>No books yet. Seed some data!</p>}
            </div>
          )}
        </>
      )}

      {tab === "orders" && (
        <>
          <h2>Orders</h2>
          {orderResult ? (
            <div style={styles.card}>
              <strong>Order placed!</strong>
              <div>ID: {orderResult.orderId}</div>
              <div>Status: {orderResult.status}</div>
              <div>Total: ${Number(orderResult.totalAmount).toFixed(2)}</div>
            </div>
          ) : (
            <p>Place an order from the Catalog tab.</p>
          )}
        </>
      )}
    </div>
  );
}
