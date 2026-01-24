-- Migration: 028_seed_exhaustive_categories.sql
-- Description: Seed an exhaustive list of categories for a typical Mart

-- 1. Ensure constraint exists for ON CONFLICT to work
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'categories_tenant_id_name_key'
    ) THEN
        ALTER TABLE public.categories ADD CONSTRAINT categories_tenant_id_name_key UNIQUE (tenant_id, name);
    END IF;
END $$;

-- 2. Seed Categories
-- Note: Subsitute '00000000-0000-0000-0000-000000000002' with your actual Store ID if needed
INSERT INTO public.categories (name, tenant_id)
VALUES 
    ('Beverages', '00000000-0000-0000-0000-000000000002'),
    ('Snacks & Biscuits', '00000000-0000-0000-0000-000000000002'),
    ('Dairy & Eggs', '00000000-0000-0000-0000-000000000002'),
    ('Bakery & Bread', '00000000-0000-0000-0000-000000000002'),
    ('Fruits & Vegetables', '00000000-0000-0000-0000-000000000002'),
    ('Meat & Poultry', '00000000-0000-0000-0000-000000000002'),
    ('Seafood', '00000000-0000-0000-0000-000000000002'),
    ('Frozen Foods', '00000000-0000-0000-0000-000000000002'),
    ('Canned & Jarred Goods', '00000000-0000-0000-0000-000000000002'),
    ('Grains & Staples (Rice/Dal)', '00000000-0000-0000-0000-000000000002'),
    ('Oil & Ghee', '00000000-0000-0000-0000-000000000002'),
    ('Breakfast & Cereal', '00000000-0000-0000-0000-000000000002'),
    ('Spices & Masalas', '00000000-0000-0000-0000-000000000002'),
    ('Salt, Sugar & Baking', '00000000-0000-0000-0000-000000000002'),
    ('Sweets & Chocolates', '00000000-0000-0000-0000-000000000002'),
    ('Baby Care', '00000000-0000-0000-0000-000000000002'),
    ('Personal Care & Beauty', '00000000-0000-0000-0000-000000000002'),
    ('Health & Pharmacy', '00000000-0000-0000-0000-000000000002'),
    ('Household & Cleaning', '00000000-0000-0000-0000-000000000002'),
    ('Pet Care', '00000000-0000-0000-0000-000000000002'),
    ('Electronics & Accessories', '00000000-0000-0000-0000-000000000002'),
    ('Stationery & Office', '00000000-0000-0000-0000-000000000002'),
    ('Tobacco & Lighter', '00000000-0000-0000-0000-000000000002'),
    ('Liquor & Alcohol', '00000000-0000-0000-0000-000000000002'),
    ('Home & Kitchen', '00000000-0000-0000-0000-000000000002'),
    ('Clothing & Accessories', '00000000-0000-0000-0000-000000000002'),
    ('Other', '00000000-0000-0000-0000-000000000002')
ON CONFLICT (tenant_id, name) DO NOTHING;
