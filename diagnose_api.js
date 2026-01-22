const API_URL = 'http://localhost:5000/api';

async function diagnose() {
    console.log('--- Starting Final API Verification ---');

    // Helper for requests
    async function apiCall(path, method = 'GET', body = null, token = null) {
        const options = {
            method,
            headers: {
                'Content-Type': 'application/json',
            },
        };
        if (body) options.body = JSON.stringify(body);
        if (token) options.headers['Authorization'] = `Bearer ${token}`;

        try {
            const res = await fetch(`${API_URL}${path}`, options);
            const data = await res.json();
            return { status: res.status, data };
        } catch (err) {
            return { error: err.message };
        }
    }

    // 1. Try to register a test user
    const timestamp = Date.now();
    const testUser = {
        email: `verified_${timestamp}@example.com`,
        password: 'password123',
        full_name: 'Verified User',
        role: 'branch_admin'
    };

    console.log('\nTesting Registration...');
    const regRes = await apiCall('/auth/register', 'POST', testUser);
    console.log('Registration status:', regRes.status);
    if (regRes.status !== 201) {
        console.log('Registration failed:', JSON.stringify(regRes.data, null, 2));
    }

    // 2. Try to login
    console.log('\nTesting Login...');
    const loginRes = await apiCall('/auth/login', 'POST', {
        email: testUser.email,
        password: testUser.password
    });
    console.log('Login result:', loginRes.status === 200 ? '✅ Success' : '❌ Failed');

    if (loginRes.status === 200) {
        const token = loginRes.data.data.accessToken;

        // 3. Try to create a product
        console.log('\nTesting Product Creation...');
        const prodRes = await apiCall('/products', 'POST', {
            name: `Verified Product ${timestamp}`,
            price: 150.50,
            costPrice: 100,
            stock: 50,
            category: 'Verified'
        }, token);
        console.log('Product creation result:', prodRes.status === 201 ? '✅ Success' : '❌ Failed');
        if (prodRes.status !== 201) console.log(JSON.stringify(prodRes.data, null, 2));

        const productId = prodRes.data?.data?.product?.id;

        // 4. Try to create an order
        if (productId) {
            console.log('\nTesting Order Creation with real product...');
            const orderRes = await apiCall('/orders', 'POST', {
                paymentMethod: 'cash',
                customerName: 'Verified Customer',
                items: [
                    { productId: productId, quantity: 2 }
                ]
            }, token);
            console.log('Order creation result:', orderRes.status === 201 ? '✅ Success' : '❌ Failed');
            if (orderRes.status !== 201) console.log(JSON.stringify(orderRes.data, null, 2));
        } else {
            console.log('\nSkipping order creation (no product ID)');
        }
    }

    console.log('\n--- Verification Complete ---');
}

diagnose();
