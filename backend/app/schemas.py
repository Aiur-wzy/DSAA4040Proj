from decimal import Decimal

from pydantic import BaseModel, Field


class AddCartItemRequest(BaseModel):
    book_id: int
    quantity: int = Field(gt=0)


class UpdateCartItemRequest(BaseModel):
    quantity: int = Field(gt=0)


class CreateBookRequest(BaseModel):
    title: str = Field(min_length=1)
    author: str | None = None
    category: str | None = None
    price: Decimal = Field(ge=0)
    stock: int = Field(ge=0)


class UpdateBookStockRequest(BaseModel):
    delta: int
