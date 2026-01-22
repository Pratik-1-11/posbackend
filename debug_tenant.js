
const API_URL = 'http://localhost:5000/api';

async function diagnoseAuth() {
    const timestamp = Date.now();
    const loginRes = await fetch(`${API_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: 'superadmin@pos.com', password: 'password123' })
    });
    const { data: { accessToken: superToken } } = await loginRes.json();

    // Onboard
    const tenantRes = await fetch(`${API_URL}/admin/tenants`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${superToken}` },
        body: JSON.stringify({ name: 'Audit', slug: `diag-${timestamp}`, contact_email: `diag_${timestamp}@test.com` })
    });
    const { data: { tenant, adminSetup } } = await tenantRes.json();
    console.log('Created Tenant:', tenant.id);

    // Login as vendor
    const vendorLogin = await fetch(`${API_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: adminSetup.email, password: adminSetup.password })
    });
    const loginData = await vendorLogin.json();
    const vendorToken = loginData.data.accessToken;
    console.log('Logged in Vendor Admin:', loginData.data.user.id);

    // Test RPC or Policy via REST
    // We can't easily call get_user_tenant_id() from REST unless exposed.
    // But we can check if they can see their own profile.
    const profileRes = await fetch(`${API_URL}/auth/me`, {
        headers: { 'Authorization': `Bearer ${vendorToken}` }
    });
    const profileData = await profileRes.json();
    console.log('Profile Tenant ID:', profileData.data.user.tenant_id);

    if (profileData.data.user.tenant_id !== tenant.id) {
        console.error('❌ MISMATCH! Expected', tenant.id, 'but got', profileData.data.user.tenant_id);
    } else {
        console.log('✅ Profile Tenant ID matches!');
    }
}

diagnoseAuth();
