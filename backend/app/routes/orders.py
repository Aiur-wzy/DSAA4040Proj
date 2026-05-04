from fastapi import APIRouter, HTTPException

from app.db import APP_USER_ID, get_connection

router = APIRouter(prefix="/orders", tags=["orders"])


@router.post("")
def place_order():
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT c.book_id, c.quantity, b.title, b.price, b.stock
                    FROM carts c
                    JOIN books b ON b.id = c.book_id
                    WHERE c.user_id = %s
                    ORDER BY c.book_id
                    FOR UPDATE OF b
                    """,
                    (APP_USER_ID,),
                )
                cart_items = cur.fetchall()

                if not cart_items:
                    raise HTTPException(status_code=400, detail="Cart is empty")

                insufficient = [
                    item for item in cart_items if item["stock"] < item["quantity"]
                ]
                if insufficient:
                    names = ", ".join(item["title"] for item in insufficient)
                    raise HTTPException(
                        status_code=409,
                        detail=f"Insufficient stock for: {names}",
                    )

                total_price = sum(item["price"] * item["quantity"] for item in cart_items)
                cur.execute(
                    "INSERT INTO orders (user_id, total_price) VALUES (%s, %s) RETURNING id, user_id, total_price, created_at",
                    (APP_USER_ID, total_price),
                )
                order = cur.fetchone()
                order_id = order["id"]

                created_items = []
                for item in cart_items:
                    cur.execute(
                        """
                        INSERT INTO order_items (order_id, book_id, quantity, price)
                        VALUES (%s, %s, %s, %s)
                        RETURNING id, order_id, book_id, quantity, price
                        """,
                        (order_id, item["book_id"], item["quantity"], item["price"]),
                    )
                    created_item = cur.fetchone()
                    created_item["title"] = item["title"]
                    created_items.append(created_item)

                    cur.execute(
                        "UPDATE books SET stock = stock - %s WHERE id = %s",
                        (item["quantity"], item["book_id"]),
                    )

                cur.execute("DELETE FROM carts WHERE user_id = %s", (APP_USER_ID,))
            conn.commit()

        return {**order, "items": created_items}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database error: {exc}") from exc


@router.get("")
def list_orders():
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT id, user_id, total_price, created_at
                    FROM orders
                    WHERE user_id = %s
                    ORDER BY created_at DESC
                    """,
                    (APP_USER_ID,),
                )
                orders = cur.fetchall()

                for order in orders:
                    cur.execute(
                        """
                        SELECT oi.id, oi.order_id, oi.book_id, b.title, oi.quantity, oi.price
                        FROM order_items oi
                        JOIN books b ON b.id = oi.book_id
                        WHERE oi.order_id = %s
                        ORDER BY oi.id
                        """,
                        (order["id"],),
                    )
                    order["items"] = cur.fetchall()

                return orders
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database error: {exc}") from exc
