import { useState } from "react";

function Cart({ cart, onUpdateItem, onRemoveItem, onPlaceOrder }) {
  const [quantities, setQuantities] = useState({});
  const items = cart?.items || [];

  const handleQuantityChange = (bookId, value) => {
    setQuantities((prev) => ({ ...prev, [bookId]: value }));
  };

  return (
    <section className="panel">
      <h2>Cart</h2>
      {items.length === 0 ? (
        <p className="muted">Your cart is empty.</p>
      ) : (
        <>
          <ul className="cart-list">
            {items.map((item) => {
              const nextQty = quantities[item.book_id] ?? item.quantity;
              const subtotal = Number(item.price) * Number(item.quantity);

              return (
                <li key={item.book_id} className="cart-item">
                  <div>
                    <h3>{item.title}</h3>
                    <p>Price: ${Number(item.price).toFixed(2)}</p>
                    <p>Quantity: {item.quantity}</p>
                    <p>Subtotal: ${subtotal.toFixed(2)}</p>
                  </div>
                  <div className="cart-actions">
                    <input
                      type="number"
                      min="1"
                      value={nextQty}
                      onChange={(event) => handleQuantityChange(item.book_id, event.target.value)}
                    />
                    <button onClick={() => onUpdateItem(item.book_id, Number(nextQty))}>Update</button>
                    <button className="danger" onClick={() => onRemoveItem(item.book_id)}>Remove</button>
                  </div>
                </li>
              );
            })}
          </ul>
          <p className="cart-total"><strong>Total:</strong> ${Number(cart.total_price || 0).toFixed(2)}</p>
        </>
      )}

      <button onClick={onPlaceOrder} disabled={items.length === 0}>Place Order</button>
    </section>
  );
}

export default Cart;
