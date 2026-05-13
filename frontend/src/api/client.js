const API = import.meta.env.VITE_API_ENDPOINT || "";
const ORDER_API = import.meta.env.VITE_ORDER_SERVICE_URL || "";

async function req(url, options = {}) {
  const res = await fetch(url, {
    headers: { "Content-Type": "application/json", ...options.headers },
    ...options,
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ message: res.statusText }));
    throw new Error(err.message || res.statusText);
  }
  return res.status === 204 ? null : res.json();
}

export const catalog = {
  list: (genre) => req(`${API}/books${genre ? `?genre=${genre}` : ""}`),
  get: (id) => req(`${API}/books/${id}`),
  create: (data) => req(`${API}/books`, { method: "POST", body: JSON.stringify(data) }),
  update: (id, data) => req(`${API}/books/${id}`, { method: "PUT", body: JSON.stringify(data) }),
  remove: (id) => req(`${API}/books/${id}`, { method: "DELETE" }),
};

export const orders = {
  list: (userId) => req(`${ORDER_API}/orders${userId ? `?userId=${userId}` : ""}`),
  get: (id) => req(`${ORDER_API}/orders/${id}`),
  place: (data) => req(`${ORDER_API}/orders`, { method: "POST", body: JSON.stringify(data) }),
  updateStatus: (id, status) =>
    req(`${ORDER_API}/orders/${id}/status`, { method: "PUT", body: JSON.stringify({ status }) }),
};
