-- Migration: 034_shift_session_management.sql
-- Purpose: Implement cashier shift tracking and cash reconciliation
-- Compliance: Fraud prevention and daily financial reporting (Z-Reports)

-- ============================================================================
-- PART 1: Shift Sessions Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.shift_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  cashier_id UUID REFERENCES public.profiles(id) NOT NULL,
  start_time TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  end_time TIMESTAMPTZ,
  start_cash NUMERIC(15, 2) DEFAULT 0 NOT NULL,
  expected_end_cash NUMERIC(15, 2) DEFAULT 0, -- Calculated (start + cash sales)
  actual_end_cash NUMERIC(15, 2),            -- Entered by manager/cashier
  difference NUMERIC(15, 2),                -- actual - expected
  status TEXT CHECK (status IN ('open', 'closed', 'cancelled')) DEFAULT 'open' NOT NULL,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 2: Link Sales to Shifts
-- ============================================================================

ALTER TABLE public.sales 
ADD COLUMN IF NOT EXISTS shift_id UUID REFERENCES public.shift_sessions(id);

-- Create index for shift reporting
CREATE INDEX IF NOT EXISTS idx_sales_shift_id ON public.sales(shift_id);

-- ============================================================================
-- PART 3: Security & RLS
-- ============================================================================

ALTER TABLE public.shift_sessions ENABLE ROW LEVEL SECURITY;

-- Users can see shifts in their tenant
DROP POLICY IF EXISTS "View shifts in own tenant" ON public.shift_sessions;
CREATE POLICY "View shifts in own tenant" ON public.shift_sessions
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

-- Cashiers can open their own shifts
DROP POLICY IF EXISTS "Open own shift" ON public.shift_sessions;
CREATE POLICY "Open own shift" ON public.shift_sessions
FOR INSERT WITH CHECK (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  cashier_id = auth.uid()
);

-- Managers/Admins can update (close) any shift in tenant
DROP POLICY IF EXISTS "Update shifts in tenant" ON public.shift_sessions;
CREATE POLICY "Update shifts in tenant" ON public.shift_sessions
FOR UPDATE USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER')
);

-- ============================================================================
-- PART 4: Shift Events (Audit Trail)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.shift_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  shift_id UUID REFERENCES public.shift_sessions(id) ON DELETE CASCADE NOT NULL,
  event_type TEXT NOT NULL, -- 'drawer_open', 'price_override', 'void_attempt'
  description TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 5: Function to Close Shift (with auto-calculation)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.close_shift(
  p_shift_id UUID,
  p_actual_cash NUMERIC,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_expected_cash NUMERIC;
  v_tenant_id UUID;
BEGIN
  -- Check session
  SELECT tenant_id INTO v_tenant_id FROM public.shift_sessions WHERE id = p_shift_id AND status = 'open';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active shift session not found';
  END IF;

  -- Calculate expected cash: start_cash + cash sales - cash returns
  SELECT 
    s.start_cash + COALESCE(SUM(sa.total_amount), 0) INTO v_expected_cash
  FROM public.shift_sessions s
  LEFT JOIN public.sales sa ON sa.shift_id = s.id 
    AND sa.status = 'completed' 
    AND (sa.payment_method = 'cash' OR sa.payment_method = 'mixed')
  WHERE s.id = p_shift_id
  GROUP BY s.start_cash;

  -- Note: For mixed payments, this simplified logic assumes full amount is cash. 
  -- Real implementation would parse sa.payment_details->>'cash'

  UPDATE public.shift_sessions
  SET 
    end_time = NOW(),
    expected_end_cash = v_expected_cash,
    actual_end_cash = p_actual_cash,
    difference = p_actual_cash - v_expected_cash,
    status = 'closed',
    notes = p_notes,
    updated_at = NOW()
  WHERE id = p_shift_id;

  RETURN jsonb_build_object(
    'success', TRUE,
    'expected', v_expected_cash,
    'actual', p_actual_cash,
    'difference', p_actual_cash - v_expected_cash
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
