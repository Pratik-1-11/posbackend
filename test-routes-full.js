
try {
    await import('./src/routes/auth.routes.js');
    console.log('Auth routes imported');
    await import('./src/routes/user.routes.js');
    console.log('User routes imported');
    await import('./src/routes/product.routes.js');
    console.log('Product routes imported');
    await import('./src/routes/order.routes.js');
    console.log('Order routes imported');
    await import('./src/routes/report.routes.js');
    console.log('Report routes imported');
    await import('./src/routes/expense.routes.js');
    console.log('Expense routes imported');
    await import('./src/routes/purchase.routes.js');
    console.log('Purchase routes imported');
    await import('./src/routes/customer.routes.js');
    console.log('Customer routes imported');
    console.log('ALL ROUTES VALID');
} catch (err) {
    console.error('IMPORT ERROR:', err);
}
