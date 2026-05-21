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
  const [userOrders, setUserOrders] = useState([]);
  const [ordersLoading, setOrdersLoading] = useState(false);
  const [userId] = useState("akuthegreat");

  useEffect(() => {
    catalog.list()
      .then(setBooks)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    if (tab !== "orders") return;
    setOrdersLoading(true);
    orders.list(userId)
      .then((data) => setUserOrders(
        [...data].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
      ))
      .catch((e) => setError(e.message))
      .finally(() => setOrdersLoading(false));
  }, [tab]);

  async function handleOrder(book) {
    try {
      await orders.place({
        userId,
        items: [{ bookId: book.bookId, title: book.title, quantity: 1, price: book.price }],
      });
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
          <h2>Orders for {userId}</h2>
          {ordersLoading ? <p>Loading…</p> : userOrders.length === 0 ? (
            <p>No orders yet — place one from the Catalog tab.</p>
          ) : (
            <div style={styles.grid}>
              {userOrders.map((o) => (
                <div key={o.orderId} style={styles.card}>
                  <div style={{ fontSize: 12, color: "#888", marginBottom: 4 }}>
                    {o.orderId.slice(0, 8)}…
                  </div>
                  <strong>{o.items?.map((i) => i.title).join(", ")}</strong>
                  <div style={{ marginTop: 4 }}>
                    <span style={{
                      fontSize: 12, padding: "2px 6px", borderRadius: 4,
                      background: o.status === "PENDING" ? "#fff3cd" : "#d4edda",
                      color: o.status === "PENDING" ? "#856404" : "#155724",
                    }}>{o.status}</span>
                  </div>
                  <div style={{ fontSize: 13, marginTop: 6 }}>
                    ${Number(o.totalAmount).toFixed(2)}
                  </div>
                  <div style={{ fontSize: 11, color: "#aaa", marginTop: 4 }}>
                    {new Date(o.createdAt).toLocaleString()}
                  </div>
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
