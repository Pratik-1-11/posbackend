-- Insert admin user (password: admin123)
-- Note: In a real application, use proper password hashing
INSERT INTO users (
  username, 
  email, 
  password_hash, 
  first_name, 
  last_name, 
  role, 
  is_active
) VALUES (
  'admin', 
  'admin@pos.com', 
  -- bcrypt hash for 'admin123' with cost factor 10
  '$2a$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',
  'System', 
  'Administrator', 
  'ADMIN', 
  true
) ON CONFLICT (username) DO NOTHING;

-- Insert cashier user (password: cashier123)
INSERT INTO users (
  username, 
  email, 
  password_hash, 
  first_name, 
  last_name, 
  role, 
  is_active
) VALUES (
  'cashier1', 
  'cashier@pos.com', 
  -- bcrypt hash for 'cashier123' with cost factor 10
  '$2a$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi',
  'John', 
  'Doe', 
  'CASHIER', 
  true
) ON CONFLICT (username) DO NOTHING;

-- Insert sample product categories
WITH categories AS (
  SELECT 'Electronics' AS name
  UNION SELECT 'Clothing'
  UNION SELECT 'Groceries'
  UNION SELECT 'Office Supplies'
)
INSERT INTO products (name, description, sku, barcode, price, cost_price, quantity_in_stock, category, is_active)
SELECT 
  CASE 
    WHEN name = 'Electronics' THEN 'Wireless Mouse'
    WHEN name = 'Clothing' THEN 'Cotton T-Shirt'
    WHEN name = 'Groceries' THEN 'Organic Apples (1kg)'
    WHEN name = 'Office Supplies' THEN 'Sticky Notes (Pack of 10)'
  END AS name,
  
  CASE 
    WHEN name = 'Electronics' THEN 'Ergonomic wireless mouse with 3-year battery life'
    WHEN name = 'Clothing' THEN '100% cotton t-shirt, available in multiple colors'
    WHEN name = 'Groceries' THEN 'Fresh organic apples, 1kg pack'
    WHEN name = 'Office Supplies' THEN 'Colorful sticky notes, 10 pads per pack'
  END AS description,
  
  'SKU-' || UPPER(SUBSTRING(REPLACE(name, ' ', ''), 1, 6)) || '-001' AS sku,
  '12345678' || LPAD(ROW_NUMBER() OVER ()::TEXT, 4, '0') AS barcode,
  
  CASE 
    WHEN name = 'Electronics' THEN 29.99
    WHEN name = 'Clothing' THEN 19.99
    WHEN name = 'Groceries' THEN 4.99
    WHEN name = 'Office Supplies' THEN 5.99
  END AS price,
  
  CASE 
    WHEN name = 'Electronics' THEN 15.00
    WHEN name = 'Clothing' THEN 8.50
    WHEN name = 'Groceries' THEN 2.50
    WHEN name = 'Office Supplies' THEN 1.99
  END AS cost_price,
  
  CASE 
    WHEN name = 'Electronics' THEN 50
    WHEN name = 'Clothing' THEN 200
    WHEN name = 'Groceries' THEN 100
    WHEN name = 'Office Supplies' THEN 150
  END AS quantity_in_stock,
  
  name AS category,
  true AS is_active
FROM categories
ON CONFLICT (sku) DO NOTHING;

-- Insert a sample order with order items
WITH new_order AS (
  INSERT INTO orders (
    customer_name,
    customer_email,
    customer_phone,
    subtotal,
    tax_amount,
    discount_amount,
    total_amount,
    payment_method,
    payment_status,
    status,
    notes,
    created_by
  ) VALUES (
    'Test Customer',
    'test@example.com',
    '+1234567890',
    54.97,  -- subtotal
    4.40,   -- tax (8%)
    0.00,   -- no discount
    59.37,  -- total
    'CARD',
    'PAID',
    'COMPLETED',
    'Test order',
    (SELECT id FROM users WHERE username = 'admin')
  )
  RETURNING id
)
INSERT INTO order_items (
  order_id,
  product_id,
  quantity,
  unit_price,
  discount_amount
)
SELECT 
  (SELECT id FROM new_order) AS order_id,
  p.id AS product_id,
  CASE 
    WHEN p.category = 'Electronics' THEN 1
    WHEN p.category = 'Clothing' THEN 2
    WHEN p.category = 'Groceries' THEN 3
    ELSE 1
  END AS quantity,
  p.price AS unit_price,
  0.00 AS discount_amount
FROM products p
WHERE p.category IN ('Electronics', 'Clothing', 'Groceries');

-- Log the completion of the seed data insertion
DO $$
BEGIN
  RAISE NOTICE 'Seed data has been successfully inserted.';
END $$;
