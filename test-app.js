
try {
    await import('./src/app.js');
    console.log('App imported successfully');
} catch (e) {
    console.error('APP IMPORT ERROR:', e);
}
