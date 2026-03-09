-- Migration: Phase 2 - Customer Relationship Management (CRM)
-- Purpose: Implement customer segmentation, loyalty programs, and communication history
-- Dependencies: Requires analytics views and customer data from Phase 1

-- ============================================================================
-- PART 1: Customer Segmentation System
-- ============================================================================

-- Customer Segments Table
CREATE TABLE IF NOT EXISTS public.customer_segments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  segment_type TEXT NOT NULL CHECK (segment_type IN ('value_based', 'behavioral', 'demographic', 'custom')),
  criteria JSONB NOT NULL, -- Flexible criteria for segment definition
  is_active BOOLEAN DEFAULT TRUE,
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Customer Segment Memberships Table
CREATE TABLE IF NOT EXISTS public.customer_segment_memberships (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  segment_id UUID NOT NULL REFERENCES public.customer_segments(id) ON DELETE CASCADE,
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  assigned_by UUID REFERENCES public.profiles(id),
  score NUMERIC(5, 2), -- Segment relevance score (0-100)
  is_active BOOLEAN DEFAULT TRUE,
  UNIQUE(customer_id, segment_id)
);

-- Customer Loyalty Programs Table
CREATE TABLE IF NOT EXISTS public.loyalty_programs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  program_type TEXT NOT NULL CHECK (program_type IN ('points', 'tier', 'cashback', 'hybrid')),
  rules JSONB NOT NULL, -- Program rules and configuration
  start_date DATE NOT NULL,
  end_date DATE,
  is_active BOOLEAN DEFAULT TRUE,
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Customer Loyalty Memberships Table
CREATE TABLE IF NOT EXISTS public.loyalty_memberships (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  program_id UUID NOT NULL REFERENCES public.loyalty_programs(id) ON DELETE CASCADE,
  membership_number TEXT UNIQUE,
  current_tier TEXT,
  points_balance INTEGER DEFAULT 0,
  total_points_earned INTEGER DEFAULT 0,
  total_points_redeemed INTEGER DEFAULT 0,
  cashback_balance NUMERIC(10, 2) DEFAULT 0,
  total_cashback_earned NUMERIC(10, 2) DEFAULT 0,
  total_cashback_redeemed NUMERIC(10, 2) DEFAULT 0,
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  last_activity_at TIMESTAMPTZ DEFAULT NOW(),
  is_active BOOLEAN DEFAULT TRUE,
  UNIQUE(customer_id, program_id)
);

-- Loyalty Transactions Table
CREATE TABLE IF NOT EXISTS public.loyalty_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  membership_id UUID NOT NULL REFERENCES public.loyalty_memberships(id) ON DELETE CASCADE,
  transaction_type TEXT NOT NULL CHECK (transaction_type IN ('earn', 'redeem', 'expire', 'adjust', 'tier_upgrade', 'tier_downgrade')),
  points_earned INTEGER DEFAULT 0,
  points_redeemed INTEGER DEFAULT 0,
  cashback_earned NUMERIC(10, 2) DEFAULT 0,
  cashback_redeemed NUMERIC(10, 2) DEFAULT 0,
  reference_id UUID, -- Reference to sale, return, or manual adjustment
  reference_type TEXT, -- 'sale', 'return', 'manual', 'expiry'
  description TEXT,
  balance_after INTEGER, -- Points balance after transaction
  cashback_balance_after NUMERIC(10, 2), -- Cashback balance after transaction
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 2: Customer Communication System
-- ============================================================================

-- Communication Templates Table
CREATE TABLE IF NOT EXISTS public.communication_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  template_type TEXT NOT NULL CHECK (template_type IN ('email', 'sms', 'push', 'in_app')),
  subject TEXT, -- For email templates
  content TEXT NOT NULL,
  variables JSONB, -- Available template variables
  is_active BOOLEAN DEFAULT TRUE,
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Customer Communications Table
CREATE TABLE IF NOT EXISTS public.customer_communications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  template_id UUID REFERENCES public.communication_templates(id),
  communication_type TEXT NOT NULL CHECK (communication_type IN ('email', 'sms', 'push', 'in_app', 'phone_call')),
  subject TEXT,
  content TEXT NOT NULL,
  recipient_address TEXT NOT NULL, -- Email, phone number, or device token
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'failed', 'bounced')),
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  error_message TEXT,
  reference_id UUID, -- Reference to related transaction or event
  reference_type TEXT, -- 'sale', 'loyalty', 'promotion', 'reminder'
  campaign_id UUID, -- Reference to marketing campaign
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Communication Preferences Table
CREATE TABLE IF NOT EXISTS public.communication_preferences (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  channel TEXT NOT NULL CHECK (channel IN ('email', 'sms', 'push', 'in_app', 'phone_call')),
  is_enabled BOOLEAN DEFAULT TRUE,
  preferred_time TIME, -- Preferred time for communications
  frequency_limit TEXT CHECK (frequency_limit IN ('immediate', 'daily', 'weekly', 'monthly', 'never')),
  last_communication_at TIMESTAMPTZ,
  communication_count_today INTEGER DEFAULT 0,
  communication_count_week INTEGER DEFAULT 0,
  communication_count_month INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(customer_id, channel)
);

-- ============================================================================
-- PART 3: Customer Feedback and Reviews
-- ============================================================================

-- Customer Feedback Table
CREATE TABLE IF NOT EXISTS public.customer_feedback (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
  branch_id UUID REFERENCES public.branches(id),
  feedback_type TEXT NOT NULL CHECK (feedback_type IN ('complaint', 'compliment', 'suggestion', 'review', 'survey')),
  rating INTEGER CHECK (rating >= 1 AND rating <= 5),
  subject TEXT,
  message TEXT NOT NULL,
  category TEXT CHECK (category IN ('product', 'service', 'staff', 'environment', 'pricing', 'other')),
  urgency TEXT DEFAULT 'normal' CHECK (urgency IN ('low', 'normal', 'high', 'urgent')),
  status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed', 'dismissed')),
  resolution_notes TEXT,
  resolved_by UUID REFERENCES public.profiles(id),
  resolved_at TIMESTAMPTZ,
  reference_id UUID, -- Reference to sale, return, or product
  reference_type TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Product Reviews Table
CREATE TABLE IF NOT EXISTS public.product_reviews (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  sale_id UUID REFERENCES public.sales(id), -- Verified purchase
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  title TEXT,
  review TEXT,
  pros TEXT,
  cons TEXT,
  would_recommend BOOLEAN,
  helpful_count INTEGER DEFAULT 0,
  is_verified_purchase BOOLEAN DEFAULT FALSE,
  is_approved BOOLEAN DEFAULT FALSE,
  approved_by UUID REFERENCES public.profiles(id),
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(customer_id, product_id)
);

-- ============================================================================
-- PART 4: Marketing Campaigns
-- ============================================================================

-- Marketing Campaigns Table
CREATE TABLE IF NOT EXISTS public.marketing_campaigns (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  campaign_type TEXT NOT NULL CHECK (campaign_type IN ('email', 'sms', 'push', 'multi_channel')),
  target_segments JSONB, -- Target customer segments
  target_criteria JSONB, -- Additional targeting criteria
  start_date TIMESTAMPTZ NOT NULL,
  end_date TIMESTAMPTZ,
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'scheduled', 'active', 'paused', 'completed', 'cancelled')),
  budget NUMERIC(12, 2),
  total_sent INTEGER DEFAULT 0,
  total_delivered INTEGER DEFAULT 0,
  total_opened INTEGER DEFAULT 0,
  total_clicked INTEGER DEFAULT 0,
  total_converted INTEGER DEFAULT 0,
  conversion_rate NUMERIC(5, 2),
  created_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Campaign Recipients Table
CREATE TABLE IF NOT EXISTS public.campaign_recipients (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  campaign_id UUID NOT NULL REFERENCES public.marketing_campaigns(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  communication_id UUID REFERENCES public.customer_communications(id),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'opened', 'clicked', 'converted', 'bounced', 'failed')),
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  opened_at TIMESTAMPTZ,
  clicked_at TIMESTAMPTZ,
  converted_at TIMESTAMPTZ,
  conversion_value NUMERIC(10, 2),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(campaign_id, customer_id)
);

-- ============================================================================
-- PART 5: CRM Functions and Procedures
-- ============================================================================

-- Function to automatically segment customers based on criteria
CREATE OR REPLACE FUNCTION auto_segment_customers(p_tenant_id UUID)
RETURNS VOID AS $$
DECLARE
  segment_record RECORD;
  customer_record RECORD;
  segment_criteria JSONB;
  customer_matches BOOLEAN;
BEGIN
  -- Process each active segment
  FOR segment_record IN 
    SELECT id, name, criteria 
    FROM public.customer_segments 
    WHERE tenant_id = p_tenant_id AND is_active = TRUE
  LOOP
    segment_criteria := segment_record.criteria;
    
    -- Remove existing memberships for this segment
    DELETE FROM public.customer_segment_memberships 
    WHERE segment_id = segment_record.id;
    
    -- Find customers matching segment criteria
    FOR customer_record IN
      SELECT c.id, c.name, 
             COUNT(DISTINCT s.id) as total_orders,
             COALESCE(SUM(s.net_amount), 0) as total_spent,
             MAX(s.created_at) as last_purchase_date,
             CURRENT_DATE - MAX(s.created_at) as days_since_last_purchase
      FROM public.customers c
      LEFT JOIN public.sales s ON c.id = s.customer_id AND s.status = 'completed'
      WHERE c.tenant_id = p_tenant_id AND c.is_active = TRUE
      GROUP BY c.id, c.name
    LOOP
      customer_matches := FALSE;
      
      -- Apply segment criteria (simplified example)
      IF segment_criteria->>'min_orders' IS NOT NULL THEN
        IF customer_record.total_orders >= (segment_criteria->>'min_orders')::INTEGER THEN
          customer_matches := TRUE;
        END IF;
      END IF;
      
      IF segment_criteria->>'min_spent' IS NOT NULL THEN
        IF customer_record.total_spent >= (segment_criteria->>'min_spent')::NUMERIC THEN
          customer_matches := TRUE;
        END IF;
      END IF;
      
      IF segment_criteria->>'max_days_inactive' IS NOT NULL THEN
        IF customer_record.days_since_last_purchase <= (segment_criteria->>'max_days_inactive')::INTEGER THEN
          customer_matches := TRUE;
        END IF;
      END IF;
      
      -- Add customer to segment if they match
      IF customer_matches THEN
        INSERT INTO public.customer_segment_memberships (
          tenant_id, customer_id, segment_id, score
        ) VALUES (
          p_tenant_id, customer_record.id, segment_record.id, 100.0
        );
      END IF;
    END LOOP;
  END LOOP;
  
  RAISE NOTICE 'Customer segmentation completed for tenant %', p_tenant_id;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate loyalty points for a sale
CREATE OR REPLACE FUNCTION calculate_loyalty_points(
  p_tenant_id UUID,
  p_customer_id UUID,
  p_sale_amount NUMERIC,
  p_sale_id UUID
)
RETURNS INTEGER AS $$
DECLARE
  points_earned INTEGER := 0;
  membership_record RECORD;
  program_record RECORD;
  base_rate NUMERIC;
BEGIN
  -- Get customer's active loyalty membership
  SELECT lm.id, lp.program_type, lp.rules 
    INTO membership_record
  FROM public.loyalty_memberships lm
    JOIN public.loyalty_programs lp ON lm.program_id = lp.id
    WHERE lm.customer_id = p_customer_id 
      AND lm.tenant_id = p_tenant_id 
      AND lm.is_active = TRUE 
      AND lp.is_active = TRUE;
  
  IF NOT FOUND THEN
    RETURN 0; -- No active loyalty membership
  END IF;
  
  -- Calculate points based on program rules
  CASE membership_record.program_type
    WHEN 'points' THEN
      -- Simple points per currency unit
      base_rate := COALESCE((membership_record.rules->>'points_per_currency')::NUMERIC, 1.0);
      points_earned := FLOOR(p_sale_amount * base_rate);
      
      -- Apply tier multipliers
      IF membership_record.current_tier = 'gold' THEN
        points_earned := points_earned * 2;
      ELSIF membership_record.current_tier = 'silver' THEN
        points_earned := points_earned * 1.5;
      END IF;
      
    WHEN 'cashback' THEN
      -- Convert cashback to points equivalent
      base_rate := COALESCE((membership_record.rules->>'cashback_percentage')::NUMERIC, 1.0);
      points_earned := FLOOR((p_sale_amount * base_rate / 100) * 10); -- 1 point = 0.1 currency unit
      
    WHEN 'hybrid' THEN
      -- Combined calculation
      base_rate := COALESCE((membership_record.rules->>'points_per_currency')::NUMERIC, 0.5);
      points_earned := FLOOR(p_sale_amount * base_rate);
  END CASE;
  
  -- Create loyalty transaction if points earned
  IF points_earned > 0 THEN
    INSERT INTO public.loyalty_transactions (
      tenant_id, membership_id, transaction_type, points_earned, 
      reference_id, reference_type, description, balance_after
    ) VALUES (
      p_tenant_id, membership_record.id, 'earn', points_earned,
      p_sale_id, 'sale', 'Points earned from purchase',
      membership_record.points_balance + points_earned
    );
    
    -- Update membership balance
    UPDATE public.loyalty_memberships 
    SET points_balance = points_balance + points_earned,
        total_points_earned = total_points_earned + points_earned,
        last_activity_at = NOW()
    WHERE id = membership_record.id;
  END IF;
  
  RETURN points_earned;
END;
$$ LANGUAGE plpgsql;

-- Function to send personalized communication
CREATE OR REPLACE FUNCTION send_customer_communication(
  p_tenant_id UUID,
  p_customer_id UUID,
  p_template_id UUID,
  p_variables JSONB DEFAULT '{}'::JSONB
)
RETURNS UUID AS $$
DECLARE
  communication_id UUID;
  template_record RECORD;
  customer_record RECORD;
  preference_record RECORD;
  processed_content TEXT;
  recipient_address TEXT;
BEGIN
  -- Get template details
  SELECT ct.template_type, ct.subject, ct.content
    INTO template_record
  FROM public.communication_templates ct
  WHERE ct.id = p_template_id AND ct.tenant_id = p_tenant_id AND ct.is_active = TRUE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Template not found or inactive';
  END IF;
  
  -- Get customer details
  SELECT c.name, c.email, c.phone
    INTO customer_record
  FROM public.customers c
  WHERE c.id = p_customer_id AND c.tenant_id = p_tenant_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Customer not found';
  END IF;
  
  -- Check communication preferences
  SELECT cp.is_enabled, cp.communication_count_today
    INTO preference_record
  FROM public.communication_preferences cp
  WHERE cp.customer_id = p_customer_id 
    AND cp.channel = template_record.template_type
    AND cp.tenant_id = p_tenant_id;
  
  -- Check if communication is allowed
  IF preference_record.is_enabled = FALSE THEN
    RAISE EXCEPTION 'Communication not allowed for this channel';
  END IF;
  
  IF preference_record.communication_count_today >= 10 THEN -- Daily limit
    RAISE EXCEPTION 'Daily communication limit exceeded';
  END IF;
  
  -- Process template variables
  processed_content := template_record.content;
  processed_content := REPLACE(processed_content, '{{customer_name}}', COALESCE(customer_record.name, 'Valued Customer'));
  
  -- Add custom variables
  IF p_variables IS NOT NULL THEN
    FOR key IN SELECT jsonb_object_keys(p_variables)
    LOOP
      processed_content := REPLACE(processed_content, '{{' || key || '}}', (p_variables->>key));
    END LOOP;
  END IF;
  
  -- Determine recipient address
  CASE template_record.template_type
    WHEN 'email' THEN recipient_address := customer_record.email;
    WHEN 'sms' THEN recipient_address := customer_record.phone;
    ELSE recipient_address := customer_record.email; -- Default fallback
  END CASE;
  
  -- Create communication record
  INSERT INTO public.customer_communications (
    tenant_id, customer_id, template_id, communication_type,
    subject, content, recipient_address, status
  ) VALUES (
    p_tenant_id, p_customer_id, p_template_id, template_record.template_type,
    template_record.subject, processed_content, recipient_address, 'pending'
  ) RETURNING id INTO communication_id;
  
  -- Update communication preferences
  UPDATE public.communication_preferences 
  SET communication_count_today = communication_count_today + 1,
      last_communication_at = NOW()
  WHERE customer_id = p_customer_id 
    AND channel = template_record.template_type
    AND tenant_id = p_tenant_id;
  
  RETURN communication_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PART 6: CRM Analytics Views
-- ============================================================================

-- Customer Segments Summary View
CREATE OR REPLACE VIEW vw_customer_segments_summary AS
SELECT 
  cs.tenant_id,
  cs.id as segment_id,
  cs.name as segment_name,
  cs.segment_type,
  COUNT(csm.customer_id) as customer_count,
  AVG(csm.score) as avg_score,
  COUNT(CASE WHEN c.is_active = TRUE THEN 1 END) as active_customers,
  COALESCE(SUM(c.total_spent), 0) as total_segment_value,
  COALESCE(AVG(c.total_spent), 0) as avg_customer_value,
  cs.created_at
FROM public.customer_segments cs
LEFT JOIN public.customer_segment_memberships csm ON cs.id = csm.segment_id
LEFT JOIN vw_customer_analytics c ON csm.customer_id = c.customer_id
WHERE cs.is_active = TRUE AND csm.is_active = TRUE
GROUP BY cs.tenant_id, cs.id, cs.name, cs.segment_type, cs.created_at
ORDER BY customer_count DESC;

-- Loyalty Program Performance View
CREATE OR REPLACE VIEW vw_loyalty_program_performance AS
SELECT 
  lp.tenant_id,
  lp.id as program_id,
  lp.name as program_name,
  lp.program_type,
  COUNT(lm.customer_id) as total_members,
  COUNT(CASE WHEN lm.is_active = TRUE THEN 1 END) as active_members,
  SUM(lm.points_balance) as total_points_outstanding,
  SUM(lm.total_points_earned) as total_points_earned,
  SUM(lm.total_points_redeemed) as total_points_redeemed,
  SUM(lm.cashback_balance) as total_cashback_outstanding,
  SUM(lm.total_cashback_earned) as total_cashback_earned,
  SUM(lm.total_cashback_redeemed) as total_cashback_redeemed,
  AVG(lm.points_balance) as avg_points_per_member,
  COUNT(CASE WHEN lm.current_tier = 'gold' THEN 1 END) as gold_members,
  COUNT(CASE WHEN lm.current_tier = 'silver' THEN 1 END) as silver_members,
  COUNT(CASE WHEN lm.current_tier = 'bronze' THEN 1 END) as bronze_members,
  lp.start_date,
  lp.is_active
FROM public.loyalty_programs lp
LEFT JOIN public.loyalty_memberships lm ON lp.id = lm.program_id
WHERE lp.is_active = TRUE
GROUP BY lp.tenant_id, lp.id, lp.name, lp.program_type, lp.start_date, lp.is_active
ORDER BY total_members DESC;

-- Customer Communication Analytics View
CREATE OR REPLACE VIEW vw_communication_analytics AS
SELECT 
  cc.tenant_id,
  cc.communication_type,
  DATE_TRUNC('day', cc.created_at) as communication_date,
  COUNT(*) as total_sent,
  COUNT(CASE WHEN cc.status = 'delivered' THEN 1 END) as delivered,
  COUNT(CASE WHEN cc.status = 'failed' THEN 1 END) as failed,
  COUNT(CASE WHEN cc.status = 'bounced' THEN 1 END) as bounced,
  ROUND((COUNT(CASE WHEN cc.status = 'delivered' THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0)), 2) as delivery_rate,
  COUNT(DISTINCT cc.customer_id) as unique_customers,
  COUNT(CASE WHEN cc.reference_type = 'sale' THEN 1 END) as sale_related,
  COUNT(CASE WHEN cc.reference_type = 'loyalty' THEN 1 END) as loyalty_related,
  COUNT(CASE WHEN cc.reference_type = 'promotion' THEN 1 END) as promotion_related
FROM public.customer_communications cc
GROUP BY cc.tenant_id, cc.communication_type, DATE_TRUNC('day', cc.created_at)
ORDER BY communication_date DESC;

-- Customer Feedback Summary View
CREATE OR REPLACE VIEW vw_customer_feedback_summary AS
SELECT 
  cf.tenant_id,
  cf.feedback_type,
  cf.category,
  cf.urgency,
  cf.status,
  DATE_TRUNC('week', cf.created_at) as week,
  COUNT(*) as total_feedback,
  AVG(cf.rating) as avg_rating,
  COUNT(CASE WHEN cf.rating >= 4 THEN 1 END) as positive_feedback,
  COUNT(CASE WHEN cf.rating <= 2 THEN 1 END) as negative_feedback,
  COUNT(CASE WHEN cf.status = 'resolved' THEN 1 END) as resolved_feedback,
  ROUND((COUNT(CASE WHEN cf.status = 'resolved' THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0)), 2) as resolution_rate
FROM public.customer_feedback cf
GROUP BY cf.tenant_id, cf.feedback_type, cf.category, cf.urgency, cf.status, DATE_TRUNC('week', cf.created_at)
ORDER BY week DESC;

-- ============================================================================
-- PART 7: Indexes for Performance
-- ============================================================================

-- CRM indexes
CREATE INDEX IF NOT EXISTS idx_customer_segments_tenant ON public.customer_segments(tenant_id);
CREATE INDEX IF NOT EXISTS idx_customer_segment_memberships_tenant_customer ON public.customer_segment_memberships(tenant_id, customer_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_programs_tenant ON public.loyalty_programs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_memberships_tenant_customer ON public.loyalty_memberships(tenant_id, customer_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_membership ON public.loyalty_transactions(membership_id);
CREATE INDEX IF NOT EXISTS idx_customer_communications_tenant_customer ON public.customer_communications(tenant_id, customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_communications_status ON public.customer_communications(status);
CREATE INDEX IF NOT EXISTS idx_communication_preferences_tenant_customer ON public.communication_preferences(tenant_id, customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_feedback_tenant ON public.customer_feedback(tenant_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_tenant_product ON public.product_reviews(tenant_id, product_id);
CREATE INDEX IF NOT EXISTS idx_marketing_campaigns_tenant ON public.marketing_campaigns(tenant_id);
CREATE INDEX IF NOT EXISTS idx_campaign_recipients_campaign_customer ON public.campaign_recipients(campaign_id, customer_id);

-- ============================================================================
-- PART 8: RLS Policies for CRM Tables
-- ============================================================================

-- Enable RLS on CRM tables
ALTER TABLE public.customer_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_segment_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.communication_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_communications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.communication_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.campaign_recipients ENABLE ROW LEVEL SECURITY;

-- RLS Policies for Customer Segments
CREATE POLICY "Users can view segments in their tenant" ON public.customer_segments
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage segments" ON public.customer_segments
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin')
);

-- RLS Policies for Loyalty Programs
CREATE POLICY "Users can view loyalty programs in their tenant" ON public.loyalty_programs
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage loyalty programs" ON public.loyalty_programs
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin')
);

-- RLS Policies for Customer Communications
CREATE POLICY "Users can view communications in their tenant" ON public.customer_communications
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage communications" ON public.customer_communications
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin')
);

-- Similar policies for other CRM tables...
CREATE POLICY "Users can view feedback in their tenant" ON public.customer_feedback
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage feedback" ON public.customer_feedback
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin')
);

-- ============================================================================
-- PART 9: Grant Permissions
-- ============================================================================

-- Grant access to CRM views
GRANT SELECT ON vw_customer_segments_summary TO authenticated;
GRANT SELECT ON vw_loyalty_program_performance TO authenticated;
GRANT SELECT ON vw_communication_analytics TO authenticated;
GRANT SELECT ON vw_customer_feedback_summary TO authenticated;

-- Grant execute permissions on CRM functions
GRANT EXECUTE ON FUNCTION auto_segment_customers TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_loyalty_points TO authenticated;
GRANT EXECUTE ON FUNCTION send_customer_communication TO authenticated;
