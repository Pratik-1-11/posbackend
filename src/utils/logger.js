import winston from 'winston';
import path from 'path';
import { fileURLToPath } from 'url';
import { config } from '../config/env.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const { combine, timestamp, printf, colorize, align } = winston.format;

// Custom log format
const logFormat = printf(({ level, message, timestamp, stack }) => {
  const logMessage = `${timestamp} ${level}: ${stack || message}`;
  return logMessage;
});

// Create logger instance
const logger = winston.createLogger({
  level: config.nodeEnv === 'production' ? 'info' : 'debug',
  format: combine(
    timestamp({
      format: 'YYYY-MM-DD HH:mm:ss',
    }),
    winston.format.errors({ stack: true }),
    config.nodeEnv === 'production'
      ? winston.format.json()
      : combine(colorize({ all: true }), align(), logFormat)
  ),
  defaultMeta: { service: 'pos-backend' },
  transports: config.nodeEnv === 'production' ? [] : [
    // Write all logs with level 'error' and below to 'error.log'
    new winston.transports.File({
      filename: path.join(__dirname, '../../logs/error.log'),
      level: 'error',
      maxsize: 5242880, // 5MB
      maxFiles: 5,
    }),
    // Write all logs with level 'info' and below to 'combined.log'
    new winston.transports.File({
      filename: path.join(__dirname, '../../logs/combined.log'),
      maxsize: 10485760, // 10MB
      maxFiles: 5,
    }),
  ],
  exitOnError: false, // Don't exit on handled exceptions
});

// Always add console logger for observability in all environments
logger.add(new winston.transports.Console({
  format: config.nodeEnv === 'production'
    ? winston.format.json()
    : combine(colorize({ all: true }), align(), logFormat),
}));

// Add file transports only if we are not in production or if needed
// Note: In many container environments like Railway/Vercel, file logging is discouraged
if (config.nodeEnv !== 'production') {
  // We already have file transports defined in the constructor
}

// Create a stream object with a 'write' function that will be used by `morgan`
logger.stream = {
  write: (message) => {
    logger.info(message.trim());
  },
};

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  logger.error(error instanceof Error ? error.stack || error.message : String(error));
  // Don't exit in development to allow for debugging
  if (config.nodeEnv === 'production') {
    process.exit(1);
  }
});

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
  const reasonText = reason instanceof Error ? reason.stack || reason.message : String(reason);
  logger.error(`Unhandled Rejection: ${reasonText}`);
  // Don't exit in development to allow for debugging
  if (config.nodeEnv === 'production') {
    process.exit(1);
  }
});

export default logger;
