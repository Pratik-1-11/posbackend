import { createServer } from 'http';
import { config } from './config/env.js';
import app from './app.js';

const httpServer = createServer(app);

// Start server
const startServer = async () => {
  try {
    httpServer.listen(config.port, () => {
      console.log(`Server running in ${config.nodeEnv} mode on port ${config.port}`);
      console.log('Connected to Supabase');
    });
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
};

startServer();

// Handle unhandled promise rejections
process.on('unhandledRejection', (err) => {
  console.error('UNHANDLED REJECTION! 💥 Shutting down...');
  console.error(err);
  httpServer.close(() => {
    process.exit(1);
  });
});

process.on('SIGTERM', () => {
  console.log('👋 SIGTERM RECEIVED. Shutting down gracefully');
  httpServer.close(() => {
    console.log('💥 Process terminated!');
  });
});
