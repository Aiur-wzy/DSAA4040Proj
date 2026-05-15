const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || "";

async function request(path, options = {}) {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {})
    },
    ...options
  });

  if (!response.ok) {
    let errorMessage = `Request failed (${response.status})`;
    try {
      const errorData = await response.json();
      errorMessage = errorData?.detail || errorData?.message || errorMessage;
    } catch {
      // Ignore JSON parse failures and keep fallback message.
    }
    throw new Error(errorMessage);
  }

  if (response.status === 204) {
    return null;
  }

  return response.json();
}

export function getHealth() {
  return request("/api/health");
}

export function getDbHealth() {
  return request("/api/health/db");
}

export function getBooks(search = "") {
  const query = search ? `?search=${encodeURIComponent(search)}` : "";
  return request(`/api/books${query}`);
}

export function getCart() {
  return request("/api/cart");
}

export function addToCart(bookId, quantity) {
  return request("/api/cart", {
    method: "POST",
    body: JSON.stringify({ book_id: bookId, quantity })
  });
}

export function updateCartItem(bookId, quantity) {
  return request(`/api/cart/${bookId}`, {
    method: "PUT",
    body: JSON.stringify({ quantity })
  });
}

export function removeCartItem(bookId) {
  return request(`/api/cart/${bookId}`, {
    method: "DELETE"
  });
}

export function placeOrder(idempotencyKey) {
  return request("/api/orders", {
    method: "POST",
    headers: idempotencyKey ? { "Idempotency-Key": idempotencyKey } : {}
  });
}

export function getOrders() {
  return request("/api/orders");
}


export function createBook(book) {
  return request("/api/admin/books", {
    method: "POST",
    body: JSON.stringify(book)
  });
}

export function updateBookStock(bookId, delta) {
  return request(`/api/admin/books/${bookId}/stock`, {
    method: "PATCH",
    body: JSON.stringify({ delta })
  });
}

export function deleteBook(bookId) {
  return request(`/api/admin/books/${bookId}`, {
    method: "DELETE"
  });
}

export function getClusterStatus() {
  return request("/api/admin/cluster/status");
}
