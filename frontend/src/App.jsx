import { useEffect, useState } from "react";
import {
  addToCart,
  getBooks,
  getCart,
  getDbHealth,
  getHealth,
  getOrders,
  placeOrder,
  removeCartItem,
  updateCartItem
} from "./api";
import AdminBooks from "./components/AdminBooks";
import BookList from "./components/BookList";
import Cart from "./components/Cart";
import OrderHistory from "./components/OrderHistory";
import MonitoringDashboard from "./components/MonitoringDashboard";
import StatusMessage from "./components/StatusMessage";

function App() {
  const [books, setBooks] = useState([]);
  const [cart, setCart] = useState({ items: [], total_price: 0 });
  const [orders, setOrders] = useState([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [backendStatus, setBackendStatus] = useState("Unknown");
  const [dbStatus, setDbStatus] = useState("Unknown");
  const [page, setPage] = useState("store");

  const refreshBooks = async (searchTerm = "") => {
    const result = await getBooks(searchTerm);
    setBooks(Array.isArray(result) ? result : result.books || []);
  };

  const refreshCart = async () => {
    const result = await getCart();
    setCart(result || { items: [], total_price: 0 });
  };

  const refreshOrders = async () => {
    const result = await getOrders();
    setOrders(Array.isArray(result) ? result : result.orders || []);
  };

  useEffect(() => {
    const initialize = async () => {
      setLoading(true);
      setError("");

      try {
        const health = await getHealth();
        setBackendStatus(health?.status || "Healthy");
      } catch (err) {
        setBackendStatus("Unavailable");
        setError(`Backend health check failed: ${err.message}`);
      }

      try {
        const dbHealth = await getDbHealth();
        setDbStatus(dbHealth?.status || "Healthy");
      } catch (err) {
        setDbStatus("Unavailable");
        setMessage(`Warning: Database health check failed (${err.message}).`);
      }

      try {
        await Promise.all([refreshBooks(), refreshCart(), refreshOrders()]);
      } catch (err) {
        setError(`Failed to load data: ${err.message}`);
      } finally {
        setLoading(false);
      }
    };

    initialize();
  }, []);

  const handleSearch = async (event) => {
    event.preventDefault();
    setError("");
    try {
      await refreshBooks(search);
    } catch (err) {
      setError(`Search failed: ${err.message}`);
    }
  };

  const handleAddToCart = async (bookId) => {
    setError("");
    setMessage("");
    try {
      await addToCart(bookId, 1);
      await refreshCart();
      setMessage("Item added to cart.");
    } catch (err) {
      setError(`Failed to add item: ${err.message}`);
    }
  };

  const handleUpdateCartItem = async (bookId, quantity) => {
    setError("");
    setMessage("");
    try {
      await updateCartItem(bookId, quantity);
      await refreshCart();
      setMessage("Cart updated.");
    } catch (err) {
      setError(`Failed to update cart item: ${err.message}`);
    }
  };

  const handleRemoveCartItem = async (bookId) => {
    setError("");
    setMessage("");
    try {
      await removeCartItem(bookId);
      await refreshCart();
      setMessage("Item removed from cart.");
    } catch (err) {
      setError(`Failed to remove cart item: ${err.message}`);
    }
  };

  const handlePlaceOrder = async () => {
    setError("");
    setMessage("");
    try {
      await placeOrder();
      await Promise.all([refreshBooks(), refreshCart(), refreshOrders()]);
      setMessage("Order placed successfully.");
    } catch (err) {
      setError(`Failed to place order: ${err.message}`);
    }
  };

  if (page === "monitoring") {
    return (
      <div className="app">
        <MonitoringDashboard onBack={() => setPage("store")} />
      </div>
    );
  }

  if (page === "admin") {
    return (
      <div className="app">
        <AdminBooks
          onBack={() => setPage("store")}
          onBooksChanged={() => Promise.all([refreshBooks(search), refreshCart()])}
        />
      </div>
    );
  }

  return (
    <div className="app">
      <header className="store-header">
        <div>
          <h1>DSAA 4040 Online Bookstore</h1>
          <p>Backend status: {backendStatus} | DB status: {dbStatus}</p>
        </div>
        <div className="header-actions">
          <button type="button" onClick={() => setPage("monitoring")}>
            Monitoring
          </button>
          <button type="button" onClick={() => setPage("admin")}>
            Admin Demo
          </button>
        </div>
      </header>

      <StatusMessage message={message} error={error} />

      {loading ? <p>Loading...</p> : null}

      <main className="grid">
        <BookList
          books={books}
          search={search}
          onSearchChange={setSearch}
          onSearch={handleSearch}
          onAddToCart={handleAddToCart}
        />

        <Cart
          cart={cart}
          onUpdateItem={handleUpdateCartItem}
          onRemoveItem={handleRemoveCartItem}
          onPlaceOrder={handlePlaceOrder}
        />
      </main>

      <OrderHistory orders={orders} />
    </div>
  );
}

export default App;
