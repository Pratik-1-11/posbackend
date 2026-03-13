-- Migration: Add stock level columns to products table
-- Purpose: Resolve "record NEW has no field max_stock_level" error in triggers
-- Date: 2026-03-13

DO $$
BEGIN
    -- Add min_stock_level if missing
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'products' 
        AND column_name = 'min_stock_level'
    ) THEN
        ALTER TABLE public.products ADD COLUMN min_stock_level INTEGER DEFAULT 0;
        RAISE NOTICE 'Added min_stock_level to products table';
    END IF;

    -- Add max_stock_level if missing
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'products' 
        AND column_name = 'max_stock_level'
    ) THEN
        ALTER TABLE public.products ADD COLUMN max_stock_level INTEGER;
        RAISE NOTICE 'Added max_stock_level to products table';
    END IF;
END $$;

-- Update trigger function check_stock_alerts if it exists to be more robust
-- (This ensures even if someone drops the columns again, we don't crash)
CREATE OR REPLACE FUNCTION public.check_stock_alerts()
RETURNS TRIGGER AS $$
DECLARE
  v_tenant_id UUID;
  v_branch_id UUID;
  v_product_id UUID;
  v_stock_quantity INTEGER;
  v_min_stock INTEGER;
  v_max_stock INTEGER;
  v_product_name TEXT;
  v_col_exists BOOLEAN;
BEGIN
  -- Get context
  v_tenant_id := NEW.tenant_id;
  v_branch_id := NEW.branch_id;
  v_product_id := NEW.id;
  v_stock_quantity := NEW.stock_quantity;
  v_product_name := NEW.name;

  -- Safely get min_stock_level if it exists on the record
  BEGIN
    v_min_stock := NEW.min_stock_level;
  EXCEPTION WHEN OTHERS THEN
    v_min_stock := 0;
  END;

  -- Safely get max_stock_level if it exists on the record
  BEGIN
    v_max_stock := NEW.max_stock_level;
  EXCEPTION WHEN OTHERS THEN
    v_max_stock := NULL;
  END;

  -- 1. Check Out of Stock
  IF v_stock_quantity <= 0 THEN
    INSERT INTO public.stock_alerts (
      tenant_id, branch_id, product_id, alert_type, 
      current_stock, min_stock_level, alert_level, message
    ) VALUES (
      v_tenant_id, v_branch_id, v_product_id, 'out_of_stock',
      v_stock_quantity, COALESCE(v_min_stock, 0), 'critical',
      '🚨 OUT OF STOCK: ' || v_product_name || ' is currently unavailable.'
    ) ON CONFLICT DO NOTHING;
    
  -- 2. Check Low Stock
  ELSIF v_min_stock IS NOT NULL AND v_stock_quantity <= v_min_stock THEN
    INSERT INTO public.stock_alerts (
      tenant_id, branch_id, product_id, alert_type, 
      current_stock, min_stock_level, alert_level, message
    ) VALUES (
      v_tenant_id, v_branch_id, v_product_id, 'low_stock',
      v_stock_quantity, v_min_stock, 'warning',
      '⚠️ LOW STOCK alert for ' || v_product_name || '. Only ' || v_stock_quantity || ' left.'
    ) ON CONFLICT DO NOTHING;
    
  -- 3. Check Excess Stock
  ELSIF v_max_stock IS NOT NULL AND v_stock_quantity >= v_max_stock THEN
    INSERT INTO public.stock_alerts (
      tenant_id, branch_id, product_id, alert_type, 
      current_stock, min_stock_level, max_stock_level, alert_level, message
    ) VALUES (
      v_tenant_id, v_branch_id, v_product_id, 'excess_stock',
      v_stock_quantity, COALESCE(v_min_stock, 0), v_max_stock, 'info',
      'ℹ️ EXCESS STOCK: ' || v_product_name || ' has reached maximum stock level (' || v_stock_quantity || ').'
    ) ON CONFLICT DO NOTHING;
  END IF;

  -- 4. Automatically resolve low/out of stock alerts if stock is replenished
  IF v_stock_quantity > COALESCE(v_min_stock, 0) THEN
    UPDATE public.stock_alerts
    SET is_resolved = TRUE,
        resolved_at = NOW(),
        resolution_notes = 'Auto-resolved: Stock replenished to ' || v_stock_quantity
    WHERE product_id = v_product_id
      AND branch_id = v_branch_id
      AND alert_type IN ('low_stock', 'out_of_stock')
      AND is_resolved = FALSE;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
