-- Create users table
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  email VARCHAR(100) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  first_name VARCHAR(50) NOT NULL,
  last_name VARCHAR(50) NOT NULL,
  role VARCHAR(20) NOT NULL CHECK (role IN ('ADMIN', 'CASHIER')),
  is_active BOOLEAN DEFAULT true,
  last_login TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create products table
CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  description TEXT,
  sku VARCHAR(50) UNIQUE,
  barcode VARCHAR(50) UNIQUE,
  price DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
  cost_price DECIMAL(10, 2) CHECK (cost_price >= 0),
  quantity_in_stock INTEGER NOT NULL DEFAULT 0 CHECK (quantity_in_stock >= 0),
  min_quantity INTEGER DEFAULT 5,
  category VARCHAR(50),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL
);

-- Create orders table
CREATE TABLE IF NOT EXISTS orders (
  id SERIAL PRIMARY KEY,
  order_number VARCHAR(20) UNIQUE NOT NULL,
  customer_name VARCHAR(100),
  customer_email VARCHAR(100),
  customer_phone VARCHAR(20),
  subtotal DECIMAL(12, 2) NOT NULL CHECK (subtotal >= 0),
  tax_amount DECIMAL(12, 2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  discount_amount DECIMAL(12, 2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
  total_amount DECIMAL(12, 2) NOT NULL CHECK (total_amount >= 0),
  payment_method VARCHAR(20) CHECK (payment_method IN ('CASH', 'CARD', 'MOBILE_PAYMENT')),
  payment_status VARCHAR(20) DEFAULT 'PENDING' CHECK (payment_status IN ('PENDING', 'PAID', 'FAILED', 'REFUNDED')),
  status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'CANCELLED')),
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL
);

-- Create order_items table
CREATE TABLE IF NOT EXISTS order_items (
  id SERIAL PRIMARY KEY,
  order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price DECIMAL(10, 2) NOT NULL CHECK (unit_price >= 0),
  discount_amount DECIMAL(10, 2) DEFAULT 0 CHECK (discount_amount >= 0),
  total_price DECIMAL(12, 2) GENERATED ALWAYS AS ((unit_price * quantity) - discount_amount) STORED,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create inventory_transactions table for tracking stock changes
CREATE TABLE IF NOT EXISTS inventory_transactions (
  id SERIAL PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  quantity_change INTEGER NOT NULL,
  transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('PURCHASE', 'SALE', 'ADJUSTMENT', 'RETURN')),
  reference_id INTEGER, -- Could reference order_id, purchase_order_id, etc.
  reference_type VARCHAR(50), -- 'ORDER', 'PURCHASE_ORDER', 'ADJUSTMENT', etc.
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  created_by INTEGER REFERENCES users(id) ON DELETE SET NULL
);

-- Create indexes for better query performance
CREATE INDEX idx_orders_created_at ON orders(created_at);
CREATE INDEX idx_orders_payment_status ON orders(payment_status);
CREATE INDEX idx_products_name ON products(name);
CREATE INDEX idx_products_sku ON products(sku);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_inventory_transactions_product_id ON inventory_transactions(product_id);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers to update updated_at columns
CREATE TRIGGER update_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_products_updated_at
BEFORE UPDATE ON products
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create function to handle inventory updates
CREATE OR REPLACE FUNCTION update_inventory()
RETURNS TRIGGER AS $$
BEGIN
  -- For INSERT on order_items (new sale)
  IF (TG_OP = 'INSERT') THEN
    -- Decrease product quantity
    UPDATE products 
    SET quantity_in_stock = quantity_in_stock - NEW.quantity,
        updated_at = NOW()
    WHERE id = NEW.product_id;
    
    -- Record inventory transaction
    INSERT INTO inventory_transactions (
      product_id, 
      quantity_change, 
      transaction_type, 
      reference_id, 
      reference_type,
      created_by
    ) VALUES (
      NEW.product_id, 
      -NEW.quantity, 
      'SALE', 
      NEW.order_id, 
      'ORDER',
      (SELECT created_by FROM orders WHERE id = NEW.order_id)
    );
    
  -- For DELETE on order_items (order item removed)
  ELSIF (TG_OP = 'DELETE') THEN
    -- Increase product quantity
    UPDATE products 
    SET quantity_in_stock = quantity_in_stock + OLD.quantity,
        updated_at = NOW()
    WHERE id = OLD.product_id;
    
    -- Record inventory transaction
    INSERT INTO inventory_transactions (
      product_id, 
      quantity_change, 
      transaction_type, 
      reference_id, 
      reference_type,
      created_by
    ) VALUES (
      OLD.product_id, 
      OLD.quantity, 
      'RETURN', 
      OLD.order_id, 
      'ORDER',
      (SELECT created_by FROM orders WHERE id = OLD.order_id)
    );
    
  -- For UPDATE on order_items (quantity changed)
  ELSIF (TG_OP = 'UPDATE' AND NEW.quantity != OLD.quantity) THEN
    -- Adjust product quantity
    UPDATE products 
    SET quantity_in_stock = quantity_in_stock + OLD.quantity - NEW.quantity,
        updated_at = NOW()
    WHERE id = NEW.product_id;
    
    -- Record inventory transaction for the difference
    INSERT INTO inventory_transactions (
      product_id, 
      quantity_change, 
      transaction_type, 
      reference_id, 
      reference_type,
      created_by,
      notes
    ) VALUES (
      NEW.product_id, 
      OLD.quantity - NEW.quantity, 
      'ADJUSTMENT', 
      NEW.order_id, 
      'ORDER',
      (SELECT created_by FROM orders WHERE id = NEW.order_id),
      'Order item quantity updated'
    );
  END IF;
  
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for order_items changes
CREATE TRIGGER order_items_inventory_trigger
AFTER INSERT OR UPDATE OR DELETE ON order_items
FOR EACH ROW EXECUTE FUNCTION update_inventory();

-- Create function to generate order numbers
CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS TRIGGER AS $$
DECLARE
  order_num TEXT;
  year_text TEXT;
  month_text TEXT;
  seq_num INTEGER;
BEGIN
  -- Get current year and month
  year_text := TO_CHAR(CURRENT_DATE, 'YY');
  month_text := TO_CHAR(CURRENT_DATE, 'MM');
  
  -- Get the next sequence number for this month
  SELECT COALESCE(MAX(SUBSTRING(order_number, 10)::INTEGER), 0) + 1 INTO seq_num
  FROM orders
  WHERE order_number LIKE 'ORD-' || year_text || month_text || '-%';
  
  -- Format the order number (e.g., ORD-2312-0001)
  order_num := 'ORD-' || year_text || month_text || '-' || LPAD(seq_num::TEXT, 4, '0');
  
  -- Set the order number
  NEW.order_number := order_num;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for order number generation
CREATE TRIGGER set_order_number
BEFORE INSERT ON orders
FOR EACH ROW
WHEN (NEW.order_number IS NULL)
EXECUTE FUNCTION generate_order_number();
