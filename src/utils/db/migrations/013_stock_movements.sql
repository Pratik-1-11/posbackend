-- Migration: Stock Movement Tracking and Inventory Ledger
-- Created: 2026-01-01

-- 1. Create stock_movements table
CREATE TABLE IF NOT EXISTS public.stock_movements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id),
  
  -- Type of movement: in, out, adjustment, return, sale, purchase, damage, expired
  type TEXT NOT NULL CHECK (type IN ('in', 'out', 'adjustment', 'return', 'sale', 'purchase', 'damage', 'expired')),
  
  quantity INTEGER NOT NULL, -- Positive for in, negative for out usually, or always positive + type?
  -- Design: Let's use signed quantity for simplicity in sums, or unsigned + type
  -- DECISION: Signed quantity. +10 for in, -5 for out.
  
  previous_stock INTEGER,
  new_stock INTEGER,
  reason TEXT,
  
  -- Links to other entities
  reference_type TEXT CHECK (reference_type IN ('sale', 'purchase', 'adjustment', 'manual')),
  reference_id UUID,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Indexes for performance
CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON public.stock_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_tenant ON public.stock_movements(tenant_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_created ON public.stock_movements(created_at DESC);

-- 3. Trigger to update product stock_quantity automatically? 
-- No, let's do it in the app layer for now to have more control, 
-- or use a function like process_stock_adjustment.

-- 4. RPC for Atomic Stock Adjustment
CREATE OR REPLACE FUNCTION adjust_stock(
  p_tenant_id UUID,
  p_product_id UUID,
  p_user_id UUID,
  p_quantity INTEGER,
  p_type TEXT,
  p_reason TEXT DEFAULT NULL,
  p_ref_type TEXT DEFAULT 'manual',
  p_ref_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_old_stock INTEGER;
  v_new_stock INTEGER;
  v_movement_id UUID;
BEGIN
  -- 1. Lock Product Row
  SELECT stock_quantity INTO v_old_stock
  FROM public.products
  WHERE id = p_product_id AND tenant_id = p_tenant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found or access denied';
  END IF;

  -- 2. Calculate New Stock
  v_new_stock := v_old_stock + p_quantity;

  -- 3. Update Product
  UPDATE public.products
  SET stock_quantity = v_new_stock,
      updated_at = NOW()
  WHERE id = p_product_id;

  -- 4. Record Movement
  INSERT INTO public.stock_movements (
    tenant_id, product_id, user_id, type, quantity, 
    previous_stock, new_stock, reason, reference_type, reference_id
  )
  VALUES (
    p_tenant_id, p_product_id, p_user_id, p_type, p_quantity,
    v_old_stock, v_new_stock, p_reason, p_ref_type, p_ref_id
  )
  RETURNING id INTO v_movement_id;

  RETURN jsonb_build_object(
    'status', 'success',
    'movement_id', v_movement_id,
    'new_stock', v_new_stock
  );
END;
$$ LANGUAGE plpgsql;
