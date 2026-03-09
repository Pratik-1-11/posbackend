-- Migration: Phase 2 - API Integration Framework
-- Purpose: Implement third-party integrations, webhooks, and external system connectivity
-- Dependencies: Requires all core systems from Phase 1 & 2

-- ============================================================================
-- PART 1: API Integration Management
-- ============================================================================

-- External Integrations Table
CREATE TABLE IF NOT EXISTS public.external_integrations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  integration_type TEXT NOT NULL CHECK (integration_type IN ('payment_gateway', 'accounting', 'crm', 'email', 'sms', 'analytics', 'inventory', 'shipping', 'custom')),
  provider TEXT NOT NULL, -- 'stripe', 'quickbooks', 'salesforce', 'sendgrid', 'twilio', etc.
  description TEXT,
  configuration JSONB NOT NULL, -- API keys, endpoints, settings
  authentication_type TEXT NOT NULL CHECK (authentication_type IN ('api_key', 'oauth2', 'basic_auth', 'bearer_token', 'webhook')),
  credentials JSONB, -- Encrypted credentials
  webhook_url TEXT,
  webhook_events TEXT[], -- Events that trigger webhooks
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'error', 'suspended')),
  last_sync_at TIMESTAMPTZ,
  sync_frequency_minutes INTEGER DEFAULT 60,
  error_count INTEGER DEFAULT 0,
  last_error TEXT,
  retry_count INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 3,
  is_bidirectional BOOLEAN DEFAULT FALSE,
  data_mapping JSONB, -- Field mapping between systems
  created_by UUID NOT NULL REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- API Endpoints Table
CREATE TABLE IF NOT EXISTS public.api_endpoints (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  integration_id UUID NOT NULL REFERENCES public.external_integrations(id) ON DELETE CASCADE,
  endpoint_name TEXT NOT NULL,
  method TEXT NOT NULL CHECK (method IN ('GET', 'POST', 'PUT', 'DELETE', 'PATCH')),
  url_template TEXT NOT NULL, -- URL with placeholders
  headers JSONB, -- Default headers
  request_template JSONB, -- Request body template
  response_mapping JSONB, -- How to map response back to our system
  rate_limit_per_minute INTEGER DEFAULT 60,
  timeout_seconds INTEGER DEFAULT 30,
  retry_policy JSONB, -- Retry configuration
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- API Logs Table
CREATE TABLE IF NOT EXISTS public.api_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  integration_id UUID REFERENCES public.external_integrations(id) ON DELETE CASCADE,
  endpoint_id UUID REFERENCES public.api_endpoints(id) ON DELETE CASCADE,
  request_id TEXT UNIQUE, -- For tracking request/response pairs
  method TEXT,
  url TEXT,
  request_headers JSONB,
  request_body TEXT,
  response_status INTEGER,
  response_headers JSONB,
  response_body TEXT,
  response_time_ms INTEGER,
  error_message TEXT,
  triggered_by UUID REFERENCES public.profiles(id),
  triggered_by_event TEXT, -- 'sale', 'customer_created', 'inventory_update', etc.
  reference_id UUID, -- Reference to related record
  reference_type TEXT, -- 'sale', 'customer', 'product', etc.
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 2: Webhook Management
-- ============================================================================

-- Webhook Subscriptions Table
CREATE TABLE IF NOT EXISTS public.webhook_subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  target_url TEXT NOT NULL,
  events TEXT[] NOT NULL, -- ['sale.created', 'customer.updated', 'inventory.low_stock']
  secret_key TEXT, -- For webhook signature verification
  active BOOLEAN DEFAULT TRUE,
  retry_policy JSONB, -- Retry configuration
  timeout_seconds INTEGER DEFAULT 10,
  rate_limit_per_hour INTEGER DEFAULT 1000,
  last_triggered_at TIMESTAMPTZ,
  success_count INTEGER DEFAULT 0,
  failure_count INTEGER DEFAULT 0,
  last_error TEXT,
  created_by UUID NOT NULL REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Webhook Delivery Logs Table
CREATE TABLE IF NOT EXISTS public.webhook_delivery_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  subscription_id UUID NOT NULL REFERENCES public.webhook_subscriptions(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  event_data JSONB NOT NULL,
  delivery_status TEXT DEFAULT 'pending' CHECK (delivery_status IN ('pending', 'delivered', 'failed', 'retrying')),
  attempt_number INTEGER DEFAULT 1,
  response_status INTEGER,
  response_body TEXT,
  response_time_ms INTEGER,
  error_message TEXT,
  scheduled_at TIMESTAMPTZ DEFAULT NOW(),
  delivered_at TIMESTAMPTZ,
  next_retry_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Webhook Events Table (Event Queue)
CREATE TABLE IF NOT EXISTS public.webhook_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  event_data JSONB NOT NULL,
  source_system TEXT DEFAULT 'pos',
  priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'critical')),
  processed BOOLEAN DEFAULT FALSE,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 3: Data Synchronization
-- ============================================================================

-- Sync Jobs Table
CREATE TABLE IF NOT EXISTS public.sync_jobs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  integration_id UUID NOT NULL REFERENCES public.external_integrations(id) ON DELETE CASCADE,
  job_type TEXT NOT NULL CHECK (job_type IN ('full_sync', 'incremental_sync', 'real_time_sync', 'manual_sync')),
  sync_direction TEXT NOT NULL CHECK (sync_direction IN ('import', 'export', 'bidirectional')),
  entity_type TEXT NOT NULL, -- 'customers', 'products', 'sales', 'inventory'
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  records_processed INTEGER DEFAULT 0,
  records_success INTEGER DEFAULT 0,
  records_failed INTEGER DEFAULT 0,
  error_summary TEXT,
  progress_percentage NUMERIC(5, 2) DEFAULT 0,
  estimated_remaining_seconds INTEGER,
  last_sync_at TIMESTAMPTZ,
  next_sync_at TIMESTAMPTZ,
  triggered_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Sync Mappings Table
CREATE TABLE IF NOT EXISTS public.sync_mappings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  integration_id UUID NOT NULL REFERENCES public.external_integrations(id) ON DELETE CASCADE,
  local_entity_type TEXT NOT NULL, -- 'customers', 'products', 'sales'
  local_field_name TEXT NOT NULL, -- 'name', 'email', 'price'
  remote_entity_type TEXT NOT NULL, -- 'Contact', 'Product', 'Invoice'
  remote_field_name TEXT NOT NULL, -- 'Name', 'Email', 'UnitPrice'
  data_type TEXT NOT NULL CHECK (data_type IN ('string', 'number', 'boolean', 'date', 'json')),
  transformation_function TEXT, -- SQL function for data transformation
  is_required BOOLEAN DEFAULT FALSE,
  default_value TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(integration_id, local_entity_type, local_field_name, remote_entity_type, remote_field_name)
);

-- Sync Conflicts Table
CREATE TABLE IF NOT EXISTS public.sync_conflicts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  sync_job_id UUID REFERENCES public.sync_jobs(id) ON DELETE CASCADE,
  integration_id UUID NOT NULL REFERENCES public.external_integrations(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL,
  local_record_id UUID,
  remote_record_id TEXT,
  conflict_type TEXT NOT NULL CHECK (conflict_type IN ('data_mismatch', 'version_conflict', 'validation_error', 'missing_reference')),
  conflict_details JSONB NOT NULL,
  resolution_action TEXT CHECK (resolution_action IN ('use_local', 'use_remote', 'merge', 'manual')),
  resolved_by UUID REFERENCES public.profiles(id),
  resolved_at TIMESTAMPTZ,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- PART 4: Integration Functions
-- ============================================================================

-- Function to trigger webhook event
CREATE OR REPLACE FUNCTION trigger_webhook_event(
  p_tenant_id UUID,
  p_event_type TEXT,
  p_event_data JSONB,
  p_priority TEXT DEFAULT 'normal'
)
RETURNS INTEGER AS $$
DECLARE
  subscription_count INTEGER := 0;
  subscription_record RECORD;
  webhook_id UUID;
BEGIN
  -- Create webhook event record
  INSERT INTO public.webhook_events (
    tenant_id, event_type, event_data, priority
  ) VALUES (
    p_tenant_id, p_event_type, p_event_data, p_priority
  );
  
  -- Find active webhook subscriptions for this event
  FOR subscription_record IN 
    SELECT * FROM public.webhook_subscriptions 
    WHERE tenant_id = p_tenant_id 
      AND active = TRUE 
      AND p_event_type = ANY(events)
  LOOP
    -- Create webhook delivery log
    INSERT INTO public.webhook_delivery_logs (
      tenant_id, subscription_id, event_type, event_data
    ) VALUES (
      p_tenant_id, subscription_record.id, p_event_type, p_event_data
    ) RETURNING id INTO webhook_id;
    
    subscription_count := subscription_count + 1;
  END LOOP;
  
  RETURN subscription_count;
END;
$$ LANGUAGE plpgsql;

-- Function to make API call
CREATE OR REPLACE FUNCTION make_api_call(
  p_integration_id UUID,
  p_endpoint_name TEXT,
  p_parameters JSONB DEFAULT '{}'::JSONB,
  p_request_body JSONB DEFAULT '{}'::JSONB
)
RETURNS TABLE (
  success BOOLEAN,
  status_code INTEGER,
  response_body TEXT,
  error_message TEXT,
  request_id TEXT
) AS $$
DECLARE
  integration_record RECORD;
  endpoint_record RECORD;
  request_id TEXT := uuid_generate_v4()::TEXT;
  final_url TEXT;
  final_headers JSONB;
  final_body TEXT;
  api_response RECORD;
BEGIN
  -- Get integration and endpoint details
  SELECT * INTO integration_record 
  FROM public.external_integrations 
  WHERE id = p_integration_id;
  
  SELECT * INTO endpoint_record 
  FROM public.api_endpoints 
  WHERE integration_id = p_integration_id AND endpoint_name = p_endpoint_name;
  
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 404, NULL, 'Endpoint not found', request_id;
    RETURN;
  END IF;
  
  -- Build final URL
  final_url := REPLACE(endpoint_record.url_template, '{tenant_id}', integration_record.tenant_id::TEXT);
  
  -- Replace parameter placeholders
  FOR key IN SELECT jsonb_object_keys(p_parameters)
  LOOP
    final_url := REPLACE(final_url, '{' || key || '}', (p_parameters->>key));
  END LOOP;
  
  -- Merge headers
  final_headers := COALESCE(endpoint_record.headers, '{}'::JSONB) || 
                   COALESCE(integration_record.configuration->>'default_headers', '{}'::JSONB);
  
  -- Build request body
  IF endpoint_record.request_template IS NOT NULL THEN
    final_body := jsonb_to_text(endpoint_record.request_template);
    
    -- Replace template variables
    FOR key IN SELECT jsonb_object_keys(p_request_body)
    LOOP
      final_body := REPLACE(final_body, '{{' || key || '}}', (p_request_body->>key));
    END LOOP;
  ELSIF p_request_body IS NOT NULL THEN
    final_body := jsonb_to_text(p_request_body);
  END IF;
  
  -- Log the API request
  INSERT INTO public.api_logs (
    tenant_id, integration_id, endpoint_id, request_id,
    method, url, request_headers, request_body
  ) VALUES (
    integration_record.tenant_id, p_integration_id, endpoint_record.id, request_id,
    endpoint_record.method, final_url, final_headers, final_body
  );
  
  -- Note: In a real implementation, you would use http extension or external function
  -- to make the actual HTTP call. This is a placeholder for the API call logic.
  
  -- Simulate API call response
  -- In production, this would be replaced with actual HTTP client call
  BEGIN
    -- Placeholder for HTTP call
    SELECT 
      TRUE as success,
      200 as status_code,
      '{"status": "success", "data": {}}'::TEXT as response_body,
      NULL::TEXT as error_message
    INTO api_response;
    
    -- Update API log with response
    UPDATE public.api_logs 
    SET response_status = api_response.status_code,
        response_body = api_response.response_body,
        response_time_ms = 150 -- Placeholder
    WHERE request_id = request_id;
    
    RETURN QUERY SELECT 
      api_response.success, 
      api_response.status_code, 
      api_response.response_body, 
      api_response.error_message, 
      request_id;
    
  EXCEPTION WHEN OTHERS THEN
    -- Update API log with error
    UPDATE public.api_logs 
    SET error_message = SQLERRM
    WHERE request_id = request_id;
    
    RETURN QUERY SELECT FALSE, 500, NULL, SQLERRM, request_id;
  END;
END;
$$ LANGUAGE plpgsql;

-- Function to sync data with external system
CREATE OR REPLACE FUNCTION sync_data_with_external(
  p_tenant_id UUID,
  p_integration_id UUID,
  p_entity_type TEXT,
  p_sync_direction TEXT DEFAULT 'export'
)
RETURNS TABLE (
  job_id UUID,
  status TEXT,
  records_processed INTEGER,
  records_success INTEGER,
  records_failed INTEGER
) AS $$
DECLARE
  job_id UUID;
  integration_record RECORD;
  sync_start TIMESTAMPTZ := NOW();
  record_count INTEGER := 0;
  success_count INTEGER := 0;
  failure_count INTEGER := 0;
BEGIN
  -- Get integration details
  SELECT * INTO integration_record 
  FROM public.external_integrations 
  WHERE id = p_integration_id AND tenant_id = p_tenant_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Integration not found';
  END IF;
  
  -- Create sync job
  INSERT INTO public.sync_jobs (
    tenant_id, integration_id, job_type, sync_direction, entity_type, status
  ) VALUES (
    p_tenant_id, p_integration_id, 'manual_sync', p_sync_direction, p_entity_type, 'running'
  ) RETURNING id INTO job_id;
  
  -- Sync based on entity type and direction
  CASE p_entity_type
    WHEN 'customers' THEN
      IF p_sync_direction = 'export' THEN
        -- Export customers to external system
        FOR record_count IN 
          SELECT id FROM public.customers 
          WHERE tenant_id = p_tenant_id AND is_active = TRUE
        LOOP
          BEGIN
            -- Make API call to export customer
            PERFORM make_api_call(
              p_integration_id,
              'customer_export',
              jsonb_build_object('customer_id', record_count),
              (SELECT jsonb_build_object(
                'name', c.name,
                'email', c.email,
                'phone', c.phone
              ) FROM public.customers c WHERE c.id = record_count)
            );
            
            success_count := success_count + 1;
          EXCEPTION WHEN OTHERS THEN
            failure_count := failure_count + 1;
          END;
        END LOOP;
      END IF;
      
    WHEN 'products' THEN
      IF p_sync_direction = 'export' THEN
        -- Export products to external system
        FOR record_count IN 
          SELECT id FROM public.products 
          WHERE tenant_id = p_tenant_id AND is_active = TRUE
        LOOP
          BEGIN
            -- Make API call to export product
            PERFORM make_api_call(
              p_integration_id,
              'product_export',
              jsonb_build_object('product_id', record_count),
              (SELECT jsonb_build_object(
                'name', p.name,
                'barcode', p.barcode,
                'category', p.category,
                'price', p.selling_price
              ) FROM public.products p WHERE p.id = record_count)
            );
            
            success_count := success_count + 1;
          EXCEPTION WHEN OTHERS THEN
            failure_count := failure_count + 1;
          END;
        END LOOP;
      END IF;
      
    WHEN 'sales' THEN
      IF p_sync_direction = 'export' THEN
        -- Export recent sales to external system
        FOR record_count IN 
          SELECT id FROM public.sales 
          WHERE tenant_id = p_tenant_id 
            AND status = 'completed'
            AND created_at >= COALESCE(integration_record.last_sync_at, '1970-01-01'::TIMESTAMPTZ)
        LOOP
          BEGIN
            -- Make API call to export sale
            PERFORM make_api_call(
              p_integration_id,
              'sale_export',
              jsonb_build_object('sale_id', record_count),
              (SELECT jsonb_build_object(
                'total_amount', s.total_amount,
                'customer_id', s.customer_id,
                'sale_date', s.created_at
              ) FROM public.sales s WHERE s.id = record_count)
            );
            
            success_count := success_count + 1;
          EXCEPTION WHEN OTHERS THEN
            failure_count := failure_count + 1;
          END;
        END LOOP;
      END IF;
  END CASE;
  
  -- Update sync job
  UPDATE public.sync_jobs 
  SET status = CASE 
        WHEN failure_count = 0 THEN 'completed'
        WHEN success_count = 0 THEN 'failed'
        ELSE 'completed'
      END,
      started_at = sync_start,
      completed_at = NOW(),
      records_processed = record_count,
      records_success = success_count,
      records_failed = failure_count,
      progress_percentage = 100
  WHERE id = job_id;
  
  -- Update integration last sync
  UPDATE public.external_integrations 
  SET last_sync_at = NOW()
  WHERE id = p_integration_id;
  
  RETURN QUERY SELECT job_id, 'completed', record_count, success_count, failure_count;
END;
$$ LANGUAGE plpgsql;

-- Function to handle webhook delivery
CREATE OR REPLACE FUNCTION process_webhook_deliveries()
RETURNS INTEGER AS $$
DECLARE
  delivery_count INTEGER := 0;
  delivery_record RECORD;
  subscription_record RECORD;
  webhook_response RECORD;
BEGIN
  -- Process pending webhook deliveries
  FOR delivery_record IN 
    SELECT wdl.*, ws.target_url, ws.secret_key, ws.timeout_seconds
    FROM public.webhook_delivery_logs wdl
    JOIN public.webhook_subscriptions ws ON wdl.subscription_id = ws.id
    WHERE wdl.delivery_status = 'pending'
      OR (wdl.delivery_status = 'retrying' AND wdl.next_retry_at <= NOW())
    ORDER BY wdl.priority DESC, wdl.created_at ASC
    LIMIT 100 -- Process in batches
  LOOP
    -- Update delivery status to processing
    UPDATE public.webhook_delivery_logs 
    SET delivery_status = 'retrying'
    WHERE id = delivery_record.id;
    
    -- In a real implementation, you would make HTTP POST request here
    -- This is a placeholder for the webhook delivery logic
    
    BEGIN
      -- Simulate webhook delivery
      SELECT 
        TRUE as success,
        200 as status_code,
        'Webhook delivered successfully' as response_body
      INTO webhook_response;
      
      -- Update delivery log
      UPDATE public.webhook_delivery_logs 
      SET delivery_status = 'delivered',
          response_status = webhook_response.status_code,
          response_body = webhook_response.response_body,
          delivered_at = NOW()
      WHERE id = delivery_record.id;
      
      -- Update subscription success count
      UPDATE public.webhook_subscriptions 
      SET success_count = success_count + 1,
          last_triggered_at = NOW()
      WHERE id = delivery_record.subscription_id;
      
      delivery_count := delivery_count + 1;
      
    EXCEPTION WHEN OTHERS THEN
      -- Update delivery log with error
      UPDATE public.webhook_delivery_logs 
      SET delivery_status = 'failed',
          error_message = SQLERRM,
          attempt_number = attempt_number + 1,
          next_retry_at = NOW() + (attempt_number * 300) * INTERVAL '1 second' -- Exponential backoff
      WHERE id = delivery_record.id;
      
      -- Update subscription failure count
      UPDATE public.webhook_subscriptions 
      SET failure_count = failure_count + 1,
          last_error = SQLERRM
      WHERE id = delivery_record.subscription_id;
    END;
  END LOOP;
  
  RETURN delivery_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PART 5: Integration Triggers
-- ============================================================================

-- Trigger for customer events
CREATE OR REPLACE FUNCTION trigger_customer_webhooks()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM trigger_webhook_event(
      NEW.tenant_id,
      'customer.created',
      jsonb_build_object(
        'customer_id', NEW.id,
        'name', NEW.name,
        'email', NEW.email,
        'phone', NEW.phone,
        'created_at', NEW.created_at
      )
    );
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM trigger_webhook_event(
      NEW.tenant_id,
      'customer.updated',
      jsonb_build_object(
        'customer_id', NEW.id,
        'name', NEW.name,
        'email', NEW.email,
        'phone', NEW.phone,
        'updated_at', NEW.updated_at
      )
    );
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM trigger_webhook_event(
      OLD.tenant_id,
      'customer.deleted',
      jsonb_build_object(
        'customer_id', OLD.id,
        'name', OLD.name,
        'deleted_at', NOW()
      )
    );
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for customer events
CREATE TRIGGER trigger_customer_webhooks_insert
AFTER INSERT ON public.customers
FOR EACH ROW
EXECUTE FUNCTION trigger_customer_webhooks();

CREATE TRIGGER trigger_customer_webhooks_update
AFTER UPDATE ON public.customers
FOR EACH ROW
EXECUTE FUNCTION trigger_customer_webhooks();

CREATE TRIGGER trigger_customer_webhooks_delete
AFTER DELETE ON public.customers
FOR EACH ROW
EXECUTE FUNCTION trigger_customer_webhooks();

-- Trigger for sale events
CREATE OR REPLACE FUNCTION trigger_sale_webhooks()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM trigger_webhook_event(
      NEW.tenant_id,
      'sale.created',
      jsonb_build_object(
        'sale_id', NEW.id,
        'total_amount', NEW.total_amount,
        'customer_id', NEW.customer_id,
        'branch_id', NEW.branch_id,
        'status', NEW.status,
        'created_at', NEW.created_at
      )
    );
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Trigger webhook for status changes
    IF OLD.status != NEW.status THEN
      PERFORM trigger_webhook_event(
        NEW.tenant_id,
        'sale.status_changed',
        jsonb_build_object(
          'sale_id', NEW.id,
          'old_status', OLD.status,
          'new_status', NEW.status,
          'updated_at', NEW.updated_at
        )
      );
    END IF;
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for sale events
CREATE TRIGGER trigger_sale_webhooks_insert
AFTER INSERT ON public.sales
FOR EACH ROW
EXECUTE FUNCTION trigger_sale_webhooks();

CREATE TRIGGER trigger_sale_webhooks_update
AFTER UPDATE ON public.sales
FOR EACH ROW
EXECUTE FUNCTION trigger_sale_webhooks();

-- Trigger for inventory events
CREATE OR REPLACE FUNCTION trigger_inventory_webhooks()
RETURNS TRIGGER AS $$
BEGIN
  -- Trigger webhook for low stock alerts
  IF NEW.stock_quantity <= NEW.min_stock_level AND OLD.stock_quantity > NEW.min_stock_level THEN
    PERFORM trigger_webhook_event(
      NEW.tenant_id,
      'inventory.low_stock',
      jsonb_build_object(
        'product_id', NEW.id,
        'name', NEW.name,
        'current_stock', NEW.stock_quantity,
        'min_stock_level', NEW.min_stock_level,
        'branch_id', NEW.branch_id,
        'alerted_at', NOW()
      ),
      'high'
    );
  END IF;
  
  -- Trigger webhook for out of stock
  IF NEW.stock_quantity = 0 AND OLD.stock_quantity > 0 THEN
    PERFORM trigger_webhook_event(
      NEW.tenant_id,
      'inventory.out_of_stock',
      jsonb_build_object(
        'product_id', NEW.id,
        'name', NEW.name,
        'branch_id', NEW.branch_id,
        'out_of_stock_at', NOW()
      ),
      'critical'
    );
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for inventory events
CREATE TRIGGER trigger_inventory_webhooks_update
AFTER UPDATE ON public.products
FOR EACH ROW
WHEN (OLD.stock_quantity IS DISTINCT FROM NEW.stock_quantity)
EXECUTE FUNCTION trigger_inventory_webhooks();

-- ============================================================================
-- PART 6: Integration Views
-- ============================================================================

-- Integration Status View
CREATE OR REPLACE VIEW vw_integration_status AS
SELECT 
  ei.tenant_id,
  ei.id as integration_id,
  ei.name,
  ei.integration_type,
  ei.provider,
  ei.status,
  ei.last_sync_at,
  ei.error_count,
  ei.last_error,
  COUNT(ae.id) as total_api_calls,
  COUNT(CASE WHEN ae.response_status >= 400 THEN 1 END) as failed_api_calls,
  ROUND((COUNT(CASE WHEN ae.response_status >= 400 THEN 1 END) * 100.0 / NULLIF(COUNT(ae.id), 0)), 2) as failure_rate,
  COUNT(ws.id) as active_webhooks,
  COUNT(CASE WHEN ws.active = TRUE THEN 1 END) as active_subscriptions
FROM public.external_integrations ei
LEFT JOIN public.api_logs ae ON ei.id = ae.integration_id
LEFT JOIN public.webhook_subscriptions ws ON ei.tenant_id = ws.tenant_id
GROUP BY ei.tenant_id, ei.id, ei.name, ei.integration_type, ei.provider, 
         ei.status, ei.last_sync_at, ei.error_count, ei.last_error
ORDER BY ei.created_at DESC;

-- Webhook Performance View
CREATE OR REPLACE VIEW vw_webhook_performance AS
SELECT 
  ws.tenant_id,
  ws.id as subscription_id,
  ws.name,
  ws.target_url,
  ws.events,
  ws.active,
  ws.success_count,
  ws.failure_count,
  ROUND((ws.success_count * 100.0 / NULLIF(ws.success_count + ws.failure_count, 0)), 2) as success_rate,
  ws.last_triggered_at,
  ws.last_error,
  COUNT(wdl.id) as total_deliveries,
  COUNT(CASE WHEN wdl.delivery_status = 'delivered' THEN 1 END) as successful_deliveries,
  COUNT(CASE WHEN wdl.delivery_status = 'failed' THEN 1 END) as failed_deliveries,
  AVG(wdl.response_time_ms) as avg_response_time_ms
FROM public.webhook_subscriptions ws
LEFT JOIN public.webhook_delivery_logs wdl ON ws.id = wdl.subscription_id
GROUP BY ws.tenant_id, ws.id, ws.name, ws.target_url, ws.events, ws.active,
         ws.success_count, ws.failure_count, ws.last_triggered_at, ws.last_error
ORDER BY ws.success_count DESC;

-- Sync Job Performance View
CREATE OR REPLACE VIEW vw_sync_job_performance AS
SELECT 
  sj.tenant_id,
  sj.id as job_id,
  ei.name as integration_name,
  sj.job_type,
  sj.entity_type,
  sj.sync_direction,
  sj.status,
  sj.records_processed,
  sj.records_success,
  sj.records_failed,
  ROUND((sj.records_success * 100.0 / NULLIF(sj.records_processed, 0)), 2) as success_rate,
  sj.started_at,
  sj.completed_at,
  EXTRACT(EPOCH FROM (sj.completed_at - sj.started_at)) as duration_seconds,
  sj.error_summary
FROM public.sync_jobs sj
LEFT JOIN public.external_integrations ei ON sj.integration_id = ei.id
ORDER BY sj.created_at DESC;

-- ============================================================================
-- PART 7: Indexes for Performance
-- ============================================================================

-- API Integration indexes
CREATE INDEX IF NOT EXISTS idx_external_integrations_tenant ON public.external_integrations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_external_integrations_status ON public.external_integrations(status);
CREATE INDEX IF NOT EXISTS idx_api_endpoints_integration ON public.api_endpoints(integration_id);
CREATE INDEX IF NOT EXISTS idx_api_logs_tenant ON public.api_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_api_logs_request_id ON public.api_logs(request_id);
CREATE INDEX IF NOT EXISTS idx_webhook_subscriptions_tenant ON public.webhook_subscriptions(tenant_id);
CREATE INDEX IF NOT EXISTS idx_webhook_delivery_logs_status ON public.webhook_delivery_logs(delivery_status);
CREATE INDEX IF NOT EXISTS idx_webhook_events_processed ON public.webhook_events(processed);
CREATE INDEX IF NOT EXISTS idx_sync_jobs_tenant ON public.sync_jobs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sync_jobs_status ON public.sync_jobs(status);
CREATE INDEX IF NOT EXISTS idx_sync_conflicts_job ON public.sync_conflicts(sync_job_id);

-- ============================================================================
-- PART 8: RLS Policies for API Integration Tables
-- ============================================================================

-- Enable RLS on API integration tables
ALTER TABLE public.external_integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_endpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_delivery_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_conflicts ENABLE ROW LEVEL SECURITY;

-- RLS Policies for External Integrations
CREATE POLICY "Users can view integrations in their tenant" ON public.external_integrations
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage integrations" ON public.external_integrations
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin')
);

-- RLS Policies for Webhook Subscriptions
CREATE POLICY "Users can view webhook subscriptions in their tenant" ON public.webhook_subscriptions
FOR SELECT USING (tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()));

CREATE POLICY "Admins can manage webhook subscriptions" ON public.webhook_subscriptions
FOR ALL USING (
  tenant_id = (SELECT tenant_id FROM public.profiles WHERE id = auth.uid()) AND
  (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('branch_admin', 'super_admin')
);

-- ============================================================================
-- PART 9: Grant Permissions
-- ============================================================================

-- Grant access to integration views
GRANT SELECT ON vw_integration_status TO authenticated;
GRANT SELECT ON vw_webhook_performance TO authenticated;
GRANT SELECT ON vw_sync_job_performance TO authenticated;

-- Grant execute permissions on integration functions
GRANT EXECUTE ON FUNCTION trigger_webhook_event TO authenticated;
GRANT EXECUTE ON FUNCTION make_api_call TO authenticated;
GRANT EXECUTE ON FUNCTION sync_data_with_external TO authenticated;
GRANT EXECUTE ON FUNCTION process_webhook_deliveries TO authenticated;

-- Grant permissions for triggers (these are executed by the system)
GRANT EXECUTE ON FUNCTION trigger_customer_webhooks TO authenticated;
GRANT EXECUTE ON FUNCTION trigger_sale_webhooks TO authenticated;
GRANT EXECUTE ON FUNCTION trigger_inventory_webhooks TO authenticated;
