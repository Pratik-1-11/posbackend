import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant } from '../utils/tenantQuery.js';

export const getDailySales = async (req, res, next) => {
    try {
        let query = supabase.from('daily_sales_summary').select('*');
        try {
            query = scopeToTenant(query, req, 'daily_sales_summary');
        } catch (err) {
            console.warn('[Report] Skipping tenant filter for daily_sales_summary: view needs update');
        }

        const { data, error } = await query.limit(30);

        if (error) {
            if (error.code === '42703') {
                console.error('[Report] daily_sales_summary view is missing tenant_id. Using unscoped fallback.');
                const { data: fallback, error: err2 } = await supabase.from('daily_sales_summary').select('*').limit(30);
                if (err2) throw err2;
                return res.status(StatusCodes.OK).json({ status: 'success', data: { stats: fallback } });
            }
            throw error;
        }

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: { stats: data }
        });
    } catch (err) {
        next(err);
    }
};

export const getCashierStats = async (req, res, next) => {
    try {
        let query = supabase.from('cashier_performance').select('*');
        try {
            query = scopeToTenant(query, req, 'cashier_performance');
        } catch (err) {
            console.warn('[Report] Skipping tenant filter for cashier_performance: view needs update');
        }

        const { data, error } = await query;

        if (error) {
            if (error.code === '42703') {
                const { data: fallback, error: err2 } = await supabase.from('cashier_performance').select('*');
                if (err2) throw err2;
                return res.status(StatusCodes.OK).json({ status: 'success', data: { stats: fallback } });
            }
            throw error;
        }

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: { stats: data }
        });
    } catch (err) {
        next(err);
    }
};

export const getStockSummary = async (req, res, next) => {
    try {
        let query = supabase.from('products').select('id, name, stock_quantity, min_stock_level');
        query = scopeToTenant(query, req, 'products');

        const { data, error } = await query
            .lt('stock_quantity', 10)
            .order('stock_quantity', { ascending: true });

        if (error) throw error;

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: { products: data }
        });
    } catch (err) {
        next(err);
    }
}

export const getExpenseSummary = async (req, res, next) => {
    try {
        let query = supabase.from('expense_summary').select('*');
        try {
            query = scopeToTenant(query, req, 'expense_summary');
        } catch (err) {
            console.warn('[Report] Skipping tenant filter for expense_summary: view needs update');
        }

        const { data, error } = await query.order('expense_date', { ascending: false });

        if (error) {
            if (error.code === '42703') {
                const { data: fallback, error: err2 } = await supabase.from('expense_summary').select('*').order('expense_date', { ascending: false });
                if (err2) throw err2;
                return res.status(StatusCodes.OK).json({ status: 'success', data: { stats: fallback } });
            }
            throw error;
        }

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: { stats: data }
        });
    } catch (err) {
        next(err);
    }
};

export const getPurchaseSummary = async (req, res, next) => {
    try {
        let query = supabase.from('purchase_summary').select('*');
        try {
            query = scopeToTenant(query, req, 'purchase_summary');
        } catch (err) {
            console.warn('[Report] Skipping tenant filter for purchase_summary: view needs update');
        }

        const { data, error } = await query.order('purchase_date', { ascending: false });

        if (error) {
            if (error.code === '42703') {
                const { data: fallback, error: err2 } = await supabase.from('purchase_summary').select('*').order('purchase_date', { ascending: false });
                if (err2) throw err2;
                return res.status(StatusCodes.OK).json({ status: 'success', data: { stats: fallback } });
            }
            throw error;
        }

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: { stats: data }
        });
    } catch (err) {
        next(err);
    }
};

export const getHealthOverview = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const todayStr = today.toISOString();

        // 1. Active Cashiers (today)
        const { data: activeCashiers } = await supabase
            .from('sales')
            .select('cashier_id')
            .eq('tenant_id', tenantId)
            .gte('created_at', todayStr);

        const uniqueCashiers = new Set(activeCashiers?.map(s => s.cashier_id)).size;

        // 2. Low Stock Count
        const { count: lowStockCount } = await supabase
            .from('products')
            .select('*', { count: 'exact', head: true })
            .eq('tenant_id', tenantId)
            .eq('is_active', true)
            .filter('stock_quantity', 'lt', 10);

        // 3. Pending Credits
        const { data: pendingCredits } = await supabase
            .from('customers')
            .select('total_credit')
            .eq('tenant_id', tenantId)
            .gt('total_credit', 0);

        const totalPendingCredits = pendingCredits?.reduce((sum, c) => sum + Number(c.total_credit), 0) || 0;

        // 4. Failed Transactions (using status and today)
        const { count: failedCount } = await supabase
            .from('sales')
            .select('*', { count: 'exact', head: true })
            .eq('tenant_id', tenantId)
            .in('status', ['cancelled', 'failed'])
            .gte('created_at', todayStr);

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: {
                activeCashiers: uniqueCashiers,
                lowStockAlerts: lowStockCount || 0,
                pendingCredits: totalPendingCredits,
                failedTransactions: failedCount || 0
            }
        });
    } catch (err) {
        next(err);
    }
};

export const getPerformanceAnalytics = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;

        // 1. Top Selling Products
        let topProductsQuery = supabase.from('product_performance').select('*');
        topProductsQuery = scopeToTenant(topProductsQuery, req, 'product_performance');
        const { data: topProducts } = await topProductsQuery.limit(5);

        // 2. Payment Method Split (Last 30 days for relevance)
        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

        const { data: paymentSplit } = await supabase
            .from('sales')
            .select('payment_method, total_amount')
            .eq('tenant_id', tenantId)
            .eq('status', 'completed')
            .gte('created_at', thirtyDaysAgo.toISOString());

        const split = paymentSplit?.reduce((acc, s) => {
            const method = s.payment_method || 'unknown';
            acc[method] = (acc[method] || 0) + Number(s.total_amount);
            return acc;
        }, {}) || {};

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: {
                topProducts: topProducts || [],
                paymentSplit: split
            }
        });
    } catch (err) {
        next(err);
    }
};

export const getVatReport = async (req, res, next) => {
    try {
        const { year, month } = req.query;
        const tenantId = req.tenant.id;

        if (!year || !month) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'Year and Month are required'
            });
        }

        const startDate = new Date(year, month - 1, 1).toISOString();
        const endDate = new Date(year, month, 0, 23, 59, 59).toISOString();

        // Query the IRD focused view
        const { data: records, error } = await supabase
            .from('ird_sales_book')
            .select('*')
            .eq('tenant_id', tenantId)
            .gte('date', startDate)
            .lte('date', endDate)
            .order('date', { ascending: true });

        if (error) {
            console.error('[VAT Report] Error fetching from ird_sales_book:', error);
            // Fallback if view doesn't exist yet
            const { data: fallback, error: err2 } = await supabase
                .from('sales')
                .select('invoice_number, created_at, customer_name, sub_total, discount_amount, taxable_amount, vat_amount, total_amount, payment_method, status')
                .eq('tenant_id', tenantId)
                .gte('created_at', startDate)
                .lte('created_at', endDate);

            if (err2) throw err2;
            return res.status(StatusCodes.OK).json({ status: 'success', data: { report: fallback, summary: {} } });
        }

        // Calculate totals
        const summary = records.reduce((acc, sale) => {
            acc.totalSales += Number(sale.total_amount);
            acc.taxableAmount += Number(sale.taxable_amount);
            acc.vatAmount += Number(sale.vat_amount);
            acc.nonTaxableAmount += Number(sale.non_taxable_amount || 0);
            return acc;
        }, {
            totalSales: 0,
            taxableAmount: 0,
            vatAmount: 0,
            nonTaxableAmount: 0
        });

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: {
                report: records,
                summary
            }
        });
    } catch (err) {
        next(err);
    }
};

export const getPurchaseBook = async (req, res, next) => {
    try {
        const { year, month } = req.query;
        const tenantId = req.tenant.id;

        if (!year || !month) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'Year and Month are required'
            });
        }

        const startDate = new Date(year, month - 1, 1).toISOString();
        const endDate = new Date(year, month, 0, 23, 59, 59).toISOString();

        // 1. Fetch Purchase Records
        const { data: records, error } = await supabase
            .from('ird_purchase_book')
            .select('*')
            .eq('tenant_id', tenantId)
            .gte('date', startDate)
            .lte('date', endDate)
            .order('date', { ascending: true });

        if (error) {
            console.error('[Purchase Book] Error fetching from ird_purchase_book:', error);
            // Fallback to raw purchases table if view issues
            const { data: fallback, error: err2 } = await supabase
                .from('purchases')
                .select('*')
                .eq('tenant_id', tenantId)
                .gte('purchase_date', startDate)
                .lte('purchase_date', endDate)

            if (err2) throw err2;
            return res.status(StatusCodes.OK).json({ status: 'success', data: { report: fallback, summary: {} } });
        }

        // 2. Calculate Summary
        const summary = records.reduce((acc, item) => {
            acc.totalImports += Number(item.import_amount || 0); // Placeholder if import exists
            acc.taxableAmount += Number(item.taxable_amount || 0);
            acc.vatAmount += Number(item.vat_amount || 0);
            acc.nonTaxableAmount += Number(item.non_taxable_amount || 0);
            return acc;
        }, {
            totalImports: 0,
            taxableAmount: 0,
            vatAmount: 0,
            nonTaxableAmount: 0
        });

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: {
                report: records,
                summary
            }
        });
    } catch (err) {
        next(err);
    }
};

export const getProductPerformance = async (req, res, next) => {

    try {
        let query = supabase.from('product_performance').select('*');
        try {
            query = scopeToTenant(query, req, 'product_performance');
        } catch (err) {
            console.warn('[Report] Skipping tenant filter for product_performance: view needs update');
        }

        const { data, error } = await query.limit(10);

        if (error) {
            if (error.code === '42703') {
                const { data: fallback, error: err2 } = await supabase.from('product_performance').select('*').limit(10);
                if (err2) throw err2;
                return res.status(StatusCodes.OK).json({ status: 'success', data: { stats: fallback } });
            }
            throw error;
        }

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: { stats: data }
        });
    } catch (err) {
        next(err);
    }
};
export const getDashboardSummary = async (req, res, next) => {
    try {
        const tenantId = req.tenant.id;
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const todayStr = today.toISOString();

        // RUN ALL QUERIES IN PARALLEL ON THE SERVER
        const [
            dailySalesResult,
            healthResult,
            performanceResult
        ] = await Promise.all([
            // 1. Daily Sales
            supabase.from('daily_sales_summary')
                .select('*')
                .eq('tenant_id', tenantId)
                .limit(7),

            // 2. Health Metrics
            Promise.all([
                supabase.from('sales').select('cashier_id').eq('tenant_id', tenantId).gte('created_at', todayStr),
                supabase.from('products').select('*', { count: 'exact', head: true }).eq('tenant_id', tenantId).eq('is_active', true).lt('stock_quantity', 10),
                supabase.from('customers').select('total_credit').eq('tenant_id', tenantId).gt('total_credit', 0),
                supabase.from('sales').select('*', { count: 'exact', head: true }).eq('tenant_id', tenantId).in('status', ['cancelled', 'failed']).gte('created_at', todayStr)
            ]),

            // 3. Performance
            Promise.all([
                supabase.from('product_performance').select('*').eq('tenant_id', tenantId).limit(5),
                supabase.from('sales').select('payment_method, total_amount')
                    .eq('tenant_id', tenantId)
                    .eq('status', 'completed')
                    .gte('created_at', new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString())
            ])
        ]);

        // Process Health
        const uniqueCashiers = new Set(healthResult[0].data?.map(s => s.cashier_id)).size;
        const totalPendingCredits = healthResult[2].data?.reduce((sum, c) => sum + Number(c.total_credit), 0) || 0;

        // Process Performance
        const split = performanceResult[1].data?.reduce((acc, s) => {
            const method = s.payment_method || 'unknown';
            acc[method] = (acc[method] || 0) + Number(s.total_amount);
            return acc;
        }, {}) || {};

        res.status(StatusCodes.OK).json({
            status: 'success',
            data: {
                dailySales: dailySalesResult.data || [],
                health: {
                    activeCashiers: uniqueCashiers,
                    lowStockAlerts: healthResult[1].count || 0,
                    pendingCredits: totalPendingCredits,
                    failedTransactions: healthResult[3].count || 0
                },
                performance: {
                    topProducts: performanceResult[0].data || [],
                    paymentSplit: split
                }
            }
        });
    } catch (err) {
        next(err);
    }
};
