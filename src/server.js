import { createServer } from 'http';
import { config } from './config/env.js';
import app from './app.js';

const httpServer = createServer(app);

// Start server
const startServer = async () => {
  try {
    console.log(`Starting server in ${config.nodeEnv} mode...`);
    console.log(`Attempting to listen on port ${config.port}...`);

    httpServer.listen(config.port, '0.0.0.0', () => {
      console.log(`🚀 Server successfully running on port ${config.port}`);
      console.log(`   Health check: http://localhost:${config.port}/health`);
    });
  } catch (error) {
    console.error('🚨 Failed to start server:', error);
    process.exit(1);
  }
};

startServer().catch(err => {
  console.error('🚨 Top-level startServer failure:', err);
  process.exit(1);
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (err) => {
  console.error('🚨 UNHANDLED REJECTION! 💥');
  console.error(err);
  if (httpServer.listening) {
    httpServer.close(() => {
      process.exit(1);
    });
  } else {
    process.exit(1);
  }
});

process.on('SIGTERM', () => {
  console.log('👋 SIGTERM RECEIVED. Shutting down gracefully');
  httpServer.close(() => {
    console.log('💥 Process terminated!');
  });
});
