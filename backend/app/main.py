from fastapi import FastAPI

from app.routes.admin_books import router as admin_books_router
from app.routes.books import router as books_router
from app.routes.cart import router as cart_router
from app.routes.cluster_status import router as cluster_status_router
from app.routes.health import router as health_router
from app.routes.orders import router as orders_router

app = FastAPI(title="Bookstore Backend API")


@app.get("/")
def root():
    return {"message": "Bookstore backend service is running"}


app.include_router(health_router, prefix="/api")
app.include_router(admin_books_router, prefix="/api/admin/books")
app.include_router(books_router, prefix="/api")
app.include_router(cart_router, prefix="/api")
app.include_router(cluster_status_router, prefix="/api/admin/cluster")
app.include_router(orders_router, prefix="/api")
