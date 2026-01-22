
const API_URL = 'http://localhost:5000/api';

async function audit() {
    console.log('🚀 DEPLOYMENT READINESS AUDIT STARTING...');

    async function safeFetch(url, options) {
        const res = await fetch(url, options);
        if (!res.ok) {
            const text = await res.text();
            console.error(`❌ Error ${res.status} at ${url}:`, text);
            throw new Error(`Request failed with status ${res.status}`);
        }
        return res.json();
    }

    // 1. LOGIN AS SUPER ADMIN
    console.log('\n--- AUTHENTICATION ---');
    const loginData = await safeFetch(`${API_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: 'superadmin@pos.com', password: 'password123' })
    });
    const superToken = loginData.data.accessToken;
    console.log('✅ Super Admin Logged In');

    // 2. CREATE AUDIT TENANT
    console.log('\n--- TENANT ONBOARDING ---');
    const timestamp = Date.now();
    const tenantPayload = {
        name: `Audit Store ${timestamp}`,
        slug: `audit-store-${timestamp}`,
        contact_email: `admin_${timestamp}@audit.com`,
        contact_phone: '9800000000',
        subscription_tier: 'pro'
    };
    const tenantData = await safeFetch(`${API_URL}/admin/tenantshouse_test`, { // intentional typo to test error handling? no, let's use real endpoint
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${superToken}` },
        body: JSON.stringify(tenantPayload)
    }).catch(async (e) => {
        // Retry with correct endpoint if I made a mistake
        return safeFetch(`${API_URL}/admin/tenants`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${superToken}` },
            body: JSON.stringify(tenantPayload)
        });
    });

    const tenantId = tenantData.data.tenant.id;
    const vendorEmail = tenantData.data.adminSetup.email;
    const vendorPassword = tenantData.data.adminSetup.password;
    console.log(`✅ Tenant Created: ${tenantId}`);

    // 3. LOGIN AS VENDOR ADMIN
    console.log('\n--- VENDOR LOGIN ---');
    const vendorLoginData = await safeFetch(`${API_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: vendorEmail, password: vendorPassword })
    });
    const vendorToken = vendorLoginData.data.accessToken;
    console.log('✅ Vendor Admin Logged In');

    // 4. FUNCTIONAL FLOW: PRODUCT -> ORDER
    console.log('\n--- FUNCTIONAL WORKFLOW ---');
    const prodData = await safeFetch(`${API_URL}/products`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${vendorToken}` },
        body: JSON.stringify({
            name: 'Audit Bread',
            price: 50,
            costPrice: 30,
            stock: 100,
            category: 'Bakery'
        })
    });
    const productId = prodData.data.product.id;
    console.log(`✅ Product Created: ${productId}`);

    const orderData = await safeFetch(`${API_URL}/orders`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${vendorToken}` },
        body: JSON.stringify({
            paymentMethod: 'cash',
            items: [{ productId, quantity: 2 }]
        })
    });
    console.log(`✅ Order Created: ${orderData.data.order.invoice_number}`);

    console.log('\n🚀 PRELIMINARY AUDIT SUCCESSFUL.');
}

audit().catch(err => {
    console.error('💥 AUDIT CRASHED:', err.message);
    process.exit(1);
});
