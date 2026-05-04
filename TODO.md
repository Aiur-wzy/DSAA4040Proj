## TODO / Verification Plan

The database foundation has been implemented but has not yet been executed against a live PostgreSQL instance.

Pending verification:

- [ ] Start PostgreSQL with Docker
- [ ] Run `database/schema.sql`
- [ ] Run `database/seed.sql`
- [ ] Run `database/test.sql`
- [ ] Run `database/place_order.sql`
- [ ] Verify that:
  - [ ] `books` contains initial seed data
  - [ ] `carts` supports upsert behavior
  - [ ] `orders` can be created
  - [ ] `order_items` stores order details
  - [ ] stock is decremented after order placement
  - [ ] cart is cleared after order placement
