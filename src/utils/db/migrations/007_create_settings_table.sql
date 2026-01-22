-- Create settings table
CREATE TABLE IF NOT EXISTS settings (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) DEFAULT 'My Local Mart',
  address TEXT DEFAULT 'Kathmandu, Nepal',
  phone VARCHAR(20) DEFAULT '9800000000',
  email VARCHAR(255) DEFAULT 'store@example.com',
  pan VARCHAR(50) DEFAULT '000000000',
  footer_message TEXT DEFAULT 'Thank you for shopping with us!',
  tax_rate DECIMAL(5, 2) DEFAULT 13.00,
  currency VARCHAR(10) DEFAULT 'NPR',
  receipt_settings JSONB DEFAULT '{"header": "Thank you for your purchase!", "footer": "Please come again!", "showTax": true, "showLogo": true}',
  notification_settings JSONB DEFAULT '{"email": true, "sms": true, "lowStock": true}',
  security_settings JSONB DEFAULT '{"twoFactorAuth": false, "sessionTimeout": 30, "requirePasswordForDelete": true}',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Use trigger to update updated_at
CREATE TRIGGER update_settings_updated_at
BEFORE UPDATE ON settings
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Seed the initial settings if not already present
INSERT INTO settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
