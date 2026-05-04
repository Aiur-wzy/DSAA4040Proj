from fastapi import APIRouter, HTTPException, Query

from app.db import get_connection

router = APIRouter(prefix="/books", tags=["books"])


@router.get("")
def list_books(search: str | None = Query(default=None)):
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                if search:
                    pattern = f"%{search}%"
                    cur.execute(
                        """
                        SELECT id, title, author, category, price, stock
                        FROM books
                        WHERE title ILIKE %s
                           OR author ILIKE %s
                           OR category ILIKE %s
                        ORDER BY id
                        """,
                        (pattern, pattern, pattern),
                    )
                else:
                    cur.execute(
                        """
                        SELECT id, title, author, category, price, stock
                        FROM books
                        ORDER BY id
                        """
                    )
                return cur.fetchall()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Database error: {exc}") from exc
