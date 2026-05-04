from fastapi import APIRouter, HTTPException

from app.db import get_connection

router = APIRouter(prefix="/health", tags=["health"])


@router.get("")
def health_check():
    return {"status": "ok", "service": "bookstore-backend"}


@router.get("/db")
def db_health_check():
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
        return {"status": "ok", "database": "connected"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Database unavailable: {exc}") from exc
