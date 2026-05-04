function BookList({ books, search, onSearchChange, onSearch, onAddToCart }) {
  return (
    <section className="panel">
      <h2>Books</h2>
      <form className="search-row" onSubmit={onSearch}>
        <input
          type="text"
          value={search}
          onChange={(event) => onSearchChange(event.target.value)}
          placeholder="Search by title, author, or category"
        />
        <button type="submit">Search</button>
      </form>

      {books.length === 0 ? (
        <p className="muted">No books found.</p>
      ) : (
        <div className="book-list">
          {books.map((book) => (
            <article key={book.id} className="book-card">
              <h3>{book.title}</h3>
              <p><strong>Author:</strong> {book.author}</p>
              <p><strong>Category:</strong> {book.category}</p>
              <p><strong>Price:</strong> ${Number(book.price).toFixed(2)}</p>
              <p><strong>Stock:</strong> {book.stock}</p>
              <button
                onClick={() => onAddToCart(book.id)}
                disabled={book.stock <= 0}
              >
                Add to Cart
              </button>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}

export default BookList;
