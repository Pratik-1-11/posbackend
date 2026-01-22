/**
 * Subscription Plan Definitions
 * Defines resource limits and feature access for each tier
 */

const PLANS = {
    basic: {
        label: 'Basic Plan',
        price: 0,
        limits: {
            products: 50,
            users: 2,
            customers: 100,
            storage_mb: 100
        },
        features: ['pos', 'sales_report']
    },
    pro: {
        label: 'Pro Plan',
        price: 29,
        limits: {
            products: 1000,
            users: 10,
            customers: 5000,
            storage_mb: 1000
        },
        features: ['pos', 'sales_report', 'inventory_management', 'customer_loyalty']
    },
    enterprise: {
        label: 'Enterprise',
        price: 99,
        limits: {
            products: 100000, // Effectively unlimited
            users: 100,
            customers: 100000,
            storage_mb: 10000
        },
        features: ['all']
    }
};

export default PLANS;
