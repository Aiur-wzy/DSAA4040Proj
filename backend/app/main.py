import os

from fastapi import FastAPI

from app.routes.admin_books import router as admin_books_router
from app.routes.books import router as books_router
from app.routes.cart import router as cart_router
from app.routes.cluster_status import router as cluster_status_router
from app.routes.health import router as health_router
from app.routes.orders import router as orders_router

app = FastAPI(title="Bookstore Backend API")
BACKEND_MODE = os.getenv("BACKEND_MODE", "all").lower()
VALID_BACKEND_MODES = {"all", "public", "admin", "monitoring"}


@app.get("/")
def root():
    return {"message": "Bookstore backend service is running", "mode": BACKEND_MODE}


if BACKEND_MODE not in VALID_BACKEND_MODES:
    raise RuntimeError(
        f"Unsupported BACKEND_MODE '{BACKEND_MODE}'. "
        f"Expected one of: {', '.join(sorted(VALID_BACKEND_MODES))}."
    )

# Health endpoints are registered in every mode so probes and smoke tests work.
app.include_router(health_router, prefix="/api")

if BACKEND_MODE in {"all", "admin"}:
    app.include_router(admin_books_router, prefix="/api/admin/books")

if BACKEND_MODE in {"all", "public"}:
    app.include_router(books_router, prefix="/api")
    app.include_router(cart_router, prefix="/api")
    app.include_router(orders_router, prefix="/api")

if BACKEND_MODE in {"all", "monitoring"}:
    app.include_router(cluster_status_router, prefix="/api/admin/cluster")
