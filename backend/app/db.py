import os

from dotenv import load_dotenv
from psycopg import connect
from psycopg.rows import dict_row

load_dotenv()


DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "bookstore")
DB_USER = os.getenv("DB_USER", "bookstore")
DB_PASSWORD = os.getenv("DB_PASSWORD", "bookstore123")


APP_USER_ID = os.getenv("APP_USER_ID", "demo-user")


def get_connection():
    return connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        row_factory=dict_row,
    )
