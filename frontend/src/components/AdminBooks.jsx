import { useEffect, useState } from "react";
import { createBook, deleteBook, getBooks, updateBookStock } from "../api";
import StatusMessage from "./StatusMessage";

const emptyForm = {
  title: "",
  author: "",
  category: "",
  price: "",
  stock: ""
};

function AdminBooks({ onBack, onBooksChanged }) {
  const [books, setBooks] = useState([]);
  const [form, setForm] = useState(emptyForm);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  const loadBooks = async () => {
    const result = await getBooks();
    setBooks(Array.isArray(result) ? result : result.books || []);
  };

  const refreshAllBookLists = async () => {
    await loadBooks();
    if (onBooksChanged) {
      await onBooksChanged();
    }
  };

  useEffect(() => {
    const initialize = async () => {
      setLoading(true);
      setError("");
      try {
        await loadBooks();
      } catch (err) {
        setError(`Failed to load books: ${err.message}`);
      } finally {
        setLoading(false);
      }
    };

    initialize();
  }, []);

  const updateFormField = (field, value) => {
    setForm((current) => ({ ...current, [field]: value }));
  };

  const validateForm = () => {
    const title = form.title.trim();
    const price = Number(form.price);
    const stock = Number(form.stock);

    if (!title) {
      return "Title is required.";
    }

    if (!Number.isFinite(price) || price < 0) {
      return "Price must be a non-negative number.";
    }

    if (!Number.isInteger(stock) || stock < 0) {
      return "Stock must be a non-negative integer.";
    }

    return "";
  };

  const handleAddBook = async (event) => {
    event.preventDefault();
    setMessage("");
    setError("");

    const validationError = validateForm();
    if (validationError) {
      setError(validationError);
      return;
    }

    setLoading(true);
    try {
      await createBook({
        title: form.title.trim(),
        author: form.author.trim() || null,
        category: form.category.trim() || null,
        price: Number(form.price),
        stock: Number(form.stock)
      });
      setForm(emptyForm);
      await refreshAllBookLists();
      setMessage("Book added.");
    } catch (err) {
      setError(`Failed to add book: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleStockChange = async (book, delta) => {
    setMessage("");
    setError("");

    if (book.stock + delta < 0) {
      setError("Stock cannot become negative.");
      return;
    }

    setLoading(true);
    try {
      await updateBookStock(book.id, delta);
      await refreshAllBookLists();
      setMessage(`Stock updated for ${book.title}.`);
    } catch (err) {
      setError(`Failed to update stock: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteBook = async (book) => {
    setMessage("");
    setError("");
    setLoading(true);
    try {
      await deleteBook(book.id);
      await refreshAllBookLists();
      setMessage(`Deleted ${book.title}.`);
    } catch (err) {
      setError(`Failed to delete book: ${err.message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="admin-page">
      <header className="admin-header">
        <div>
          <h1>Admin Demo: Book Catalog</h1>
          <p className="muted">
            Simple unauthenticated course demo for catalog and inventory changes.
          </p>
        </div>
        <button type="button" onClick={onBack}>Back to Store</button>
      </header>

      <StatusMessage message={message} error={error} />
      {loading ? <p>Working...</p> : null}

      <section className="panel admin-form-panel">
        <h2>Add Book</h2>
        <form className="admin-form" onSubmit={handleAddBook}>
          <label>
            Title
            <input
              value={form.title}
              onChange={(event) => updateFormField("title", event.target.value)}
              placeholder="Book title"
            />
          </label>
          <label>
            Author
            <input
              value={form.author}
              onChange={(event) => updateFormField("author", event.target.value)}
              placeholder="Author"
            />
          </label>
          <label>
            Category
            <input
              value={form.category}
              onChange={(event) => updateFormField("category", event.target.value)}
              placeholder="Category"
            />
          </label>
          <label>
            Price
            <input
              type="number"
              min="0"
              step="0.01"
              value={form.price}
              onChange={(event) => updateFormField("price", event.target.value)}
              placeholder="0.00"
            />
          </label>
          <label>
            Stock
            <input
              type="number"
              min="0"
              step="1"
              value={form.stock}
              onChange={(event) => updateFormField("stock", event.target.value)}
              placeholder="0"
            />
          </label>
          <button type="submit" disabled={loading}>Add Book</button>
        </form>
      </section>

      <section className="panel">
        <h2>Current Books</h2>
        <div className="admin-book-list">
          {books.map((book) => (
            <article className="admin-book-row" key={book.id}>
              <div>
                <strong>#{book.id}: {book.title}</strong>
                <p className="muted">
                  {book.author || "Unknown author"} · {book.category || "Uncategorized"}
                </p>
                <p>${book.price} · Stock: {book.stock}</p>
              </div>
              <div className="admin-book-actions">
                <button type="button" onClick={() => handleStockChange(book, 1)} disabled={loading}>
                  + Stock
                </button>
                <button
                  type="button"
                  onClick={() => handleStockChange(book, -1)}
                  disabled={loading || book.stock <= 0}
                >
                  - Stock
                </button>
                <button
                  type="button"
                  className="danger"
                  onClick={() => handleDeleteBook(book)}
                  disabled={loading}
                >
                  Delete
                </button>
              </div>
            </article>
          ))}
          {!books.length && !loading ? <p className="muted">No books found.</p> : null}
        </div>
      </section>
    </div>
  );
}

export default AdminBooks;
