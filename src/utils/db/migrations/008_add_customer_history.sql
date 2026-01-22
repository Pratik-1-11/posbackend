-- Migration: Add Customer Profile History Tracking
-- Created: 2025-12-31

-- 1. Create a table to store profile change logs
CREATE TABLE IF NOT EXISTS public.customer_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
  field_name TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  changed_by UUID REFERENCES auth.users(id),
  changed_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Create a function to log changes
CREATE OR REPLACE FUNCTION log_customer_changes()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'UPDATE') THEN
    -- Log name change
    IF (OLD.name IS DISTINCT FROM NEW.name) THEN
      INSERT INTO public.customer_history (customer_id, field_name, old_value, new_value)
      VALUES (OLD.id, 'name', OLD.name, NEW.name);
    END IF;

    -- Log phone change
    IF (OLD.phone IS DISTINCT FROM NEW.phone) THEN
      INSERT INTO public.customer_history (customer_id, field_name, old_value, new_value)
      VALUES (OLD.id, 'phone', OLD.phone, NEW.phone);
    END IF;

    -- Log email change
    IF (OLD.email IS DISTINCT FROM NEW.email) THEN
      INSERT INTO public.customer_history (customer_id, field_name, old_value, new_value)
      VALUES (OLD.id, 'email', OLD.email, NEW.email);
    END IF;

    -- Log address change
    IF (OLD.address IS DISTINCT FROM NEW.address) THEN
      INSERT INTO public.customer_history (customer_id, field_name, old_value, new_value)
      VALUES (OLD.id, 'address', OLD.address, NEW.address);
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Create the trigger
DROP TRIGGER IF EXISTS customer_history_trigger ON public.customers;
CREATE TRIGGER customer_history_trigger
AFTER UPDATE ON public.customers
FOR EACH ROW EXECUTE FUNCTION log_customer_changes();

-- 4. Enable RLS for history
ALTER TABLE public.customer_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "View history" ON public.customer_history;
CREATE POLICY "View history" ON public.customer_history 
FOR SELECT TO authenticated USING (true);
