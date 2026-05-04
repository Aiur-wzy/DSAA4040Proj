-- 1) View current catalog.
SELECT * FROM books ORDER BY id;

-- 2) Add two books to demo-user cart; increment quantity on conflict.
INSERT INTO carts (user_id, book_id, quantity)
VALUES
    ('demo-user', 1, 1),
    ('demo-user', 7, 2)
ON CONFLICT (user_id, book_id)
DO UPDATE SET
    quantity = carts.quantity + EXCLUDED.quantity,
    updated_at = CURRENT_TIMESTAMP;

-- 3) View cart with joined book details.
SELECT
    c.id AS cart_id,
    c.user_id,
    c.book_id,
    b.title,
    b.price,
    c.quantity,
    (b.price * c.quantity) AS line_total,
    c.updated_at
FROM carts c
JOIN books b ON b.id = c.book_id
WHERE c.user_id = 'demo-user'
ORDER BY c.id;

-- 4) Create a simple order from current cart contents and return created order row.
WITH cart_total AS (
    SELECT COALESCE(SUM(b.price * c.quantity), 0)::NUMERIC(10, 2) AS total_price
    FROM carts c
    JOIN books b ON b.id = c.book_id
    WHERE c.user_id = 'demo-user'
)
INSERT INTO orders (user_id, total_price, status)
SELECT 'demo-user', total_price, 'CREATED'
FROM cart_total
RETURNING *;
