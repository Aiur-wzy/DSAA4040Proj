BEGIN;

DO $$
DECLARE
    v_user_id VARCHAR(100) := 'demo-user';
    v_order_id INT;
    v_total_price NUMERIC(10, 2);
    v_missing_stock_count INT;
BEGIN
    -- Ensure cart is not empty for this user.
    IF NOT EXISTS (SELECT 1 FROM carts WHERE user_id = v_user_id) THEN
        RAISE EXCEPTION 'Cart is empty for user %', v_user_id;
    END IF;

    -- Lock related book rows to avoid concurrent stock changes during order placement.
    PERFORM 1
    FROM books b
    JOIN carts c ON c.book_id = b.id
    WHERE c.user_id = v_user_id
    FOR UPDATE;

    -- Validate stock availability for every cart line.
    SELECT COUNT(*) INTO v_missing_stock_count
    FROM carts c
    JOIN books b ON b.id = c.book_id
    WHERE c.user_id = v_user_id
      AND b.stock < c.quantity;

    IF v_missing_stock_count > 0 THEN
        RAISE EXCEPTION 'Insufficient stock for one or more cart items for user %', v_user_id;
    END IF;

    -- Compute order total using current catalog prices.
    SELECT COALESCE(SUM(b.price * c.quantity), 0)::NUMERIC(10, 2)
    INTO v_total_price
    FROM carts c
    JOIN books b ON b.id = c.book_id
    WHERE c.user_id = v_user_id;

    -- Create order header.
    INSERT INTO orders (user_id, total_price, status)
    VALUES (v_user_id, v_total_price, 'CREATED')
    RETURNING id INTO v_order_id;

    -- Persist item-level details with purchase-time price snapshot.
    INSERT INTO order_items (order_id, book_id, quantity, price)
    SELECT
        v_order_id,
        c.book_id,
        c.quantity,
        b.price
    FROM carts c
    JOIN books b ON b.id = c.book_id
    WHERE c.user_id = v_user_id;

    -- Deduct inventory.
    UPDATE books b
    SET stock = b.stock - c.quantity
    FROM carts c
    WHERE c.user_id = v_user_id
      AND b.id = c.book_id;

    -- Clear cart after successful persistence.
    DELETE FROM carts
    WHERE user_id = v_user_id;
END $$;

COMMIT;
