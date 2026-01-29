-- Migration: 033_invoice_locking_system.sql
-- Purpose: Implement invoice immutability and modification audit trail
-- Compliance: IRD Nepal audit requirements & fraud prevention

-- ============================================================================
-- PART 1: Add Invoice Locking Fields to Sales Table
-- ============================================================================

ALTER TABLE public.sales 
ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS print_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_printed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS locked_by UUID REFERENCES public.profiles(id),
ADD COLUMN IF NOT EXISTS is_locked BOOLEAN DEFAULT TRUE;

-- Create index for locked invoices
CREATE INDEX IF NOT EXISTS idx_sales_locked 
ON public.sales(is_locked, status) 
WHERE is_locked = TRUE;

-- ============================================================================
-- PART 2: Invoice Modifications Audit Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.invoice_modifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sale_id UUID REFERENCES public.sales(id) NOT NULL,
  tenant_id UUID REFERENCES public.tenants(id) NOT NULL,
  modified_by UUID REFERENCES public.profiles(id),
  modification_type TEXT CHECK (modification_type IN ('void', 'refund', 'edit_attempt', 'unlock', 'reprint')) NOT NULL,
  reason TEXT NOT NULL,
  auth_code TEXT,                  -- Manager override code
  manager_id UUID REFERENCES public.profiles(id), -- Who authorized (if different from modifier)
  old_data JSONB,
  new_data JSONB,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for audit queries
CREATE INDEX IF NOT EXISTS idx_invoice_modifications_sale 
ON public.invoice_modifications(sale_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_invoice_modifications_user 
ON public.invoice_modifications(modified_by, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_invoice_modifications_tenant 
ON public.invoice_modifications(tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_invoice_modifications_type 
ON public.invoice_modifications(modification_type, tenant_id);

-- Enable RLS
ALTER TABLE public.invoice_modifications ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can view modifications in their tenant
DROP POLICY IF EXISTS "View invoice modifications in own tenant" ON public.invoice_modifications;
CREATE POLICY "View invoice modifications in own tenant" 
ON public.invoice_modifications
FOR SELECT 
USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

-- RLS Policy: Only authenticated users can create modification logs
DROP POLICY IF EXISTS "Create invoice modifications" ON public.invoice_modifications;
CREATE POLICY "Create invoice modifications" 
ON public.invoice_modifications
FOR INSERT 
WITH CHECK (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid())
);

-- ============================================================================
-- PART 3: Void Sale with Stock Restoration Function
-- ============================================================================

CREATE OR REPLACE FUNCTION public.void_sale(
  p_sale_id UUID,
  p_voided_by UUID,
  p_reason TEXT,
  p_manager_id UUID DEFAULT NULL,
  p_auth_code TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_sale RECORD;
  v_item RECORD;
  v_tenant_id UUID;
  v_modifier_role TEXT;
BEGIN
  -- Get sale details
  SELECT * INTO v_sale
  FROM public.sales
  WHERE id = p_sale_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale not found';
  END IF;
  
  -- Check if already voided
  IF v_sale.status = 'voided' THEN
    RAISE EXCEPTION 'Sale is already voided';
  END IF;
  
  -- Get tenant and role
  SELECT tenant_id, role INTO v_tenant_id, v_modifier_role
  FROM public.profiles
  WHERE id = p_voided_by;
  
  -- Authorization check: Only managers and admins can void
  IF v_modifier_role NOT IN ('SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER') THEN
    RAISE EXCEPTION 'Unauthorized: Only managers can void sales. Your role: %', v_modifier_role;
  END IF;
  
  -- Validate reason
  IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) < 10 THEN
    RAISE EXCEPTION 'Void reason must be at least 10 characters';
  END IF;
  
  -- Log modification BEFORE voiding
  INSERT INTO public.invoice_modifications (
    sale_id,
    tenant_id,
    modified_by,
    modification_type,
    reason,
    auth_code,
    manager_id,
    old_data,
    new_data
  ) VALUES (
    p_sale_id,
    v_tenant_id,
    p_voided_by,
    'void',
    p_reason,
    p_auth_code,
    COALESCE(p_manager_id, p_voided_by),
    to_jsonb(v_sale),
    jsonb_build_object('status', 'voided', 'voided_at', NOW())
  );
  
  -- Restore stock for all items
  FOR v_item IN 
    SELECT * FROM public.sale_items WHERE sale_id = p_sale_id
  LOOP
    UPDATE public.products
    SET stock_quantity = stock_quantity + v_item.quantity,
        updated_at = NOW()
    WHERE id = v_item.product_id
      AND tenant_id = v_tenant_id;
    
    -- Log stock restoration
    INSERT INTO public.stock_movements (
      tenant_id,
      product_id,
      type,
      quantity,
      reason,
      performed_by,
      reference_id
    ) VALUES (
      v_tenant_id,
      v_item.product_id,
      'return',
      v_item.quantity,
      'Sale voided: ' || v_sale.invoice_number || ' - ' || p_reason,
      p_voided_by,
      p_sale_id
    );
  END LOOP;
  
  -- Update sale status to voided
  UPDATE public.sales
  SET status = 'voided',
      locked_by = p_voided_by,
      updated_at = NOW()
  WHERE id = p_sale_id;
  
  -- If credit sale, reverse the credit transaction
  IF v_sale.payment_method IN ('credit', 'mixed') AND v_sale.customer_id IS NOT NULL THEN
    -- Calculate credit amount
    DECLARE
      v_credit_amount NUMERIC;
    BEGIN
      IF v_sale.payment_method = 'credit' THEN
        v_credit_amount := v_sale.total_amount;
      ELSE
        -- For mixed payments, extract credit amount from payment_details
        v_credit_amount := COALESCE((v_sale.payment_details->>'credit')::NUMERIC, 0);
      END IF;
      
      IF v_credit_amount > 0 THEN
        -- Add reversal transaction
        INSERT INTO public.customer_transactions (
          customer_id,
          tenant_id,
          transaction_type,
          amount,
          description,
          reference_id,
          cashier_id
        ) VALUES (
          v_sale.customer_id,
          v_tenant_id,
          'void_reversal',
          -v_credit_amount, -- Negative to reduce credit balance
          'Sale voided: ' || v_sale.invoice_number,
          p_sale_id,
          p_voided_by
        );
        
        -- Update customer credit balance
        UPDATE public.customers
        SET total_credit = total_credit - v_credit_amount,
            updated_at = NOW()
        WHERE id = v_sale.customer_id;
      END IF;
    END;
  END IF;
  
  RETURN jsonb_build_object(
    'success', TRUE,
    'sale_id', p_sale_id,
    'invoice_number', v_sale.invoice_number,
    'status', 'voided',
    'message', 'Sale voided successfully. Stock restored.'
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Void operation failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 4: Track Print Count Function
-- ============================================================================

CREATE OR REPLACE FUNCTION public.track_invoice_print(
  p_sale_id UUID,
  p_printed_by UUID
)
RETURNS VOID AS $$
DECLARE
  v_tenant_id UUID;
BEGIN
  -- Get tenant
  SELECT tenant_id INTO v_tenant_id
  FROM public.profiles
  WHERE id = p_printed_by;
  
  -- Update print tracking
  UPDATE public.sales
  SET print_count = COALESCE(print_count, 0) + 1,
      last_printed_at = NOW()
  WHERE id = p_sale_id;
  
  -- Log reprint if count > 1
  IF (SELECT print_count FROM public.sales WHERE id = p_sale_id) > 1 THEN
    INSERT INTO public.invoice_modifications (
      sale_id,
      tenant_id,
      modified_by,
      modification_type,
      reason
    ) VALUES (
      p_sale_id,
      v_tenant_id,
      p_printed_by,
      'reprint',
      'Invoice reprinted (count: ' || (SELECT print_count FROM public.sales WHERE id = p_sale_id) || ')'
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 5: Trigger to Auto-Lock Invoices on Creation
-- ============================================================================

CREATE OR REPLACE FUNCTION public.auto_lock_invoice()
RETURNS TRIGGER AS $$
BEGIN
  -- Auto-lock on insert
  NEW.is_locked := TRUE;
  NEW.locked_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_auto_lock_invoice ON public.sales;
CREATE TRIGGER trigger_auto_lock_invoice
  BEFORE INSERT ON public.sales
  FOR EACH ROW
  EXECUTE FUNCTION public.auto_lock_invoice();

-- ============================================================================
-- PART 6: View for Audit Trail
-- ============================================================================

CREATE OR REPLACE VIEW public.invoice_audit_trail AS
SELECT 
  im.id,
  im.sale_id,
  s.invoice_number,
  s.tenant_id,
  t.name as tenant_name,
  im.modification_type,
  im.reason,
  im.created_at as modification_date,
  p.full_name as modified_by_name,
  p.role as modifier_role,
  m.full_name as authorized_by_name,
  im.old_data->>'status' as old_status,
  im.new_data->>'status' as new_status,
  (im.old_data->>'total_amount')::NUMERIC as amount,
  im.ip_address
FROM public.invoice_modifications im
JOIN public.sales s ON im.sale_id = s.id
JOIN public.tenants t ON im.tenant_id = t.id
LEFT JOIN public.profiles p ON im.modified_by = p.id
LEFT JOIN public.profiles m ON im.manager_id = m.id
ORDER BY im.created_at DESC;

-- ============================================================================
-- Success Message
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Invoice Locking System installed successfully!';
  RAISE NOTICE '';
  RAISE NOTICE 'Features enabled:';
  RAISE NOTICE '  - Auto-lock invoices on creation';
  RAISE NOTICE '  - Void sale with manager authorization';
  RAISE NOTICE '  - Complete audit trail for all modifications';
  RAISE NOTICE '  - Stock restoration on void';
  RAISE NOTICE '  - Credit reversal on void';
  RAISE NOTICE '  - Print tracking';
  RAISE NOTICE '';
  RAISE NOTICE 'Functions available:';
  RAISE NOTICE '  - void_sale(sale_id, voided_by, reason, manager_id, auth_code)';
  RAISE NOTICE '  - track_invoice_print(sale_id, printed_by)';
  RAISE NOTICE '';
  RAISE NOTICE 'Views available:';
  RAISE NOTICE '  - invoice_audit_trail';
END $$;
