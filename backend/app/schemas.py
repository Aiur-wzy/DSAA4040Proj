from pydantic import BaseModel, Field


class AddCartItemRequest(BaseModel):
    book_id: int
    quantity: int = Field(gt=0)


class UpdateCartItemRequest(BaseModel):
    quantity: int = Field(gt=0)
