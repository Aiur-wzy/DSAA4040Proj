from fastapi import APIRouter, HTTPException

from app.db import APP_USER_ID, get_connection
from app.schemas import AddCartItemRequest, UpdateCartItemRequest

router = APIRouter(prefix="/cart", tags=["cart"])


def fetch_cart(user_id: str):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT c.book_id, b.title, b.author, b.price, c.quantity,
                       (b.price * c.quantity) AS subtotal
                FROM carts c
                JOIN books b ON b.id = c.book_id
                WHERE c.user_id = %s
                ORDER BY c.book_id
                """,
                (user_id,),
            )
            items = cur.fetchall()
            total = sum(item["subtotal"] for item in items)
            return {"user_id": user_id, "items": items, "total_price": total}


@router.get("")
def get_cart():
    try:
        return fetch_cart(APP_USER_ID)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database error: {exc}") from exc


@router.post("")
def add_to_cart(payload: AddCartItemRequest):
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM books WHERE id = %s", (payload.book_id,))
                if not cur.fetchone():
                    raise HTTPException(status_code=404, detail="Book not found")

                cur.execute(
                    """
                    INSERT INTO carts (user_id, book_id, quantity)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (user_id, book_id)
                    DO UPDATE SET quantity = carts.quantity + EXCLUDED.quantity
                    """,
                    (APP_USER_ID, payload.book_id, payload.quantity),
                )
            conn.commit()
        return fetch_cart(APP_USER_ID)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database error: {exc}") from exc


@router.put("/{book_id}")
def update_cart_item(book_id: int, payload: UpdateCartItemRequest):
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT 1 FROM carts WHERE user_id = %s AND book_id = %s",
                    (APP_USER_ID, book_id),
                )
                if not cur.fetchone():
                    raise HTTPException(status_code=404, detail="Cart item not found")

                cur.execute(
                    """
                    UPDATE carts
                    SET quantity = %s
                    WHERE user_id = %s AND book_id = %s
                    """,
                    (payload.quantity, APP_USER_ID, book_id),
                )
            conn.commit()
        return fetch_cart(APP_USER_ID)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database error: {exc}") from exc


@router.delete("/{book_id}")
def delete_cart_item(book_id: int):
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "DELETE FROM carts WHERE user_id = %s AND book_id = %s RETURNING book_id",
                    (APP_USER_ID, book_id),
                )
                if not cur.fetchone():
                    raise HTTPException(status_code=404, detail="Cart item not found")
            conn.commit()
        return fetch_cart(APP_USER_ID)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database error: {exc}") from exc
