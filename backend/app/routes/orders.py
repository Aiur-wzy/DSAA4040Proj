from uuid import uuid4

from fastapi import APIRouter, Header, HTTPException
from psycopg.errors import UniqueViolation

from app.db import APP_USER_ID, ensure_order_idempotency_schema, get_connection

router = APIRouter(prefix="/orders", tags=["orders"])


def _fetch_order(cur, order_id=None, idempotency_key=None):
    if order_id is not None:
        cur.execute(
            """
            SELECT id, user_id, total_price, status, idempotency_key, created_at
            FROM orders
            WHERE id = %s AND user_id = %s
            """,
            (order_id, APP_USER_ID),
        )
    else:
        cur.execute(
            """
            SELECT id, user_id, total_price, status, idempotency_key, created_at
            FROM orders
            WHERE user_id = %s AND idempotency_key = %s
            """,
            (APP_USER_ID, idempotency_key),
        )
    order = cur.fetchone()
    if not order:
        return None

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
    return order


@router.post("")
def place_order(idempotency_key: str | None = Header(default=None, alias="Idempotency-Key")):
    # Legacy clients without Idempotency-Key keep the old non-idempotent behavior by
    # receiving a unique server-side key for this one request. The frontend and scripts
    # now send Idempotency-Key so timeout/retry/failover ambiguity is safe.
    order_key = (idempotency_key or "").strip() or f"legacy-{uuid4()}"

    try:
        ensure_order_idempotency_schema()
        with get_connection() as conn:
            with conn.cursor() as cur:
                if idempotency_key:
                    existing_order = _fetch_order(cur, idempotency_key=order_key)
                    if existing_order:
                        return existing_order

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
                try:
                    cur.execute(
                        """
                        INSERT INTO orders (user_id, total_price, idempotency_key)
                        VALUES (%s, %s, %s)
                        RETURNING id, user_id, total_price, status, idempotency_key, created_at
                        """,
                        (APP_USER_ID, total_price, order_key),
                    )
                except UniqueViolation:
                    conn.rollback()
                    with conn.cursor() as retry_cur:
                        existing_order = _fetch_order(retry_cur, idempotency_key=order_key)
                    if existing_order:
                        return existing_order
                    raise

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
        ensure_order_idempotency_schema()
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT id, user_id, total_price, status, idempotency_key, created_at
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
