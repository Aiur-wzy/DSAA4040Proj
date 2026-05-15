import os

from dotenv import load_dotenv
from psycopg import connect
from psycopg.rows import dict_row

load_dotenv()


DB_HOST = os.getenv("DB_HOST", "localhost")
DB_WRITE_HOST = os.getenv("DB_WRITE_HOST") or DB_HOST
DB_READ_HOST = os.getenv("DB_READ_HOST") or DB_WRITE_HOST
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "bookstore")
DB_USER = os.getenv("DB_USER", "bookstore")
DB_PASSWORD = os.getenv("DB_PASSWORD", "bookstore123")


APP_USER_ID = os.getenv("APP_USER_ID", "demo-user")


def get_connection():
    return connect(
        host=DB_WRITE_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        row_factory=dict_row,
    )


def ensure_order_idempotency_schema():
    """Migrate existing demo databases for Idempotency-Key support."""
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                ALTER TABLE orders
                ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(128)
                """
            )
            cur.execute(
                """
                UPDATE orders
                SET idempotency_key = 'legacy-existing-' || id::text
                WHERE idempotency_key IS NULL
                """
            )
            cur.execute(
                """
                ALTER TABLE orders ALTER COLUMN idempotency_key SET NOT NULL
                """
            )
            cur.execute(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS orders_user_id_idempotency_key_uidx
                ON orders (user_id, idempotency_key)
                """
            )
        conn.commit()
