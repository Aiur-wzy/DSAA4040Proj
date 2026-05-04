function OrderHistory({ orders }) {
  return (
    <section className="panel">
      <h2>Order History</h2>
      {orders.length === 0 ? (
        <p className="muted">No orders yet.</p>
      ) : (
        <div className="orders">
          {orders.map((order) => (
            <article key={order.id} className="order-card">
              <h3>Order #{order.id}</h3>
              <p><strong>Total:</strong> ${Number(order.total_price).toFixed(2)}</p>
              <p><strong>Status:</strong> {order.status}</p>
              <p><strong>Created:</strong> {new Date(order.created_at).toLocaleString()}</p>
              <ul>
                {(order.items || []).map((item, idx) => (
                  <li key={`${order.id}-${idx}`}>
                    {item.title} × {item.quantity} @ ${Number(item.price).toFixed(2)}
                  </li>
                ))}
              </ul>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}

export default OrderHistory;
