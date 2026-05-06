from fastapi import APIRouter, HTTPException

from app.db import get_connection
from app.schemas import CreateBookRequest, UpdateBookStockRequest

router = APIRouter(tags=["admin-books"])


def fetch_book(cur, book_id: int):
    cur.execute(
        """
        SELECT id, title, author, category, price, stock
        FROM books
        WHERE id = %s
        """,
        (book_id,),
    )
    return cur.fetchone()


@router.post("")
def create_book(payload: CreateBookRequest):
    if not payload.title.strip():
        raise HTTPException(status_code=400, detail="Title is required")

    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO books (title, author, category, price, stock)
                    VALUES (%s, %s, %s, %s, %s)
                    RETURNING id, title, author, category, price, stock
                    """,
                    (
                        payload.title.strip(),
                        payload.author,
                        payload.category,
                        payload.price,
                        payload.stock,
                    ),
                )
                book = cur.fetchone()
            conn.commit()
        return book
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database error: {exc}") from exc


@router.patch("/{book_id}/stock")
def update_book_stock(book_id: int, payload: UpdateBookStockRequest):
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE books
                    SET stock = stock + %s
                    WHERE id = %s
                      AND stock + %s >= 0
                    RETURNING id, title, author, category, price, stock
                    """,
                    (payload.delta, book_id, payload.delta),
                )
                book = cur.fetchone()

                if book:
                    conn.commit()
                    return book

                existing_book = fetch_book(cur, book_id)
                if not existing_book:
                    raise HTTPException(status_code=404, detail="Book not found")

                raise HTTPException(
                    status_code=409,
                    detail="Stock update would make stock negative",
                )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database error: {exc}") from exc


@router.delete("/{book_id}")
def delete_book(book_id: int):
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                existing_book = fetch_book(cur, book_id)
                if not existing_book:
                    raise HTTPException(status_code=404, detail="Book not found")

                cur.execute(
                    "SELECT 1 FROM order_items WHERE book_id = %s LIMIT 1",
                    (book_id,),
                )
                if cur.fetchone():
                    raise HTTPException(
                        status_code=409,
                        detail="Cannot delete book because it is referenced by order history",
                    )

                cur.execute(
                    """
                    DELETE FROM books
                    WHERE id = %s
                    RETURNING id, title, author, category, price, stock
                    """,
                    (book_id,),
                )
                deleted_book = cur.fetchone()
            conn.commit()
        return deleted_book
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database error: {exc}") from exc
