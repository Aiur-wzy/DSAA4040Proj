from fastapi import FastAPI

from app.routes.books import router as books_router
from app.routes.cart import router as cart_router
from app.routes.health import router as health_router
from app.routes.orders import router as orders_router

app = FastAPI(title="Bookstore Backend API")


@app.get("/")
def root():
    return {"message": "Bookstore backend service is running"}


app.include_router(health_router, prefix="/api")
app.include_router(books_router, prefix="/api")
app.include_router(cart_router, prefix="/api")
app.include_router(orders_router, prefix="/api")
