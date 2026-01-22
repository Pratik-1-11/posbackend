import { StatusCodes } from 'http-status-codes';
import logger from '../utils/logger.js';

export const notFound = (req, res) => {
  res.status(StatusCodes.NOT_FOUND).json({
    status: 'error',
    message: `Cannot ${req.method} ${req.originalUrl}`,
  });
};

export const errorHandler = (err, req, res, next) => {
  const statusCode = err.statusCode || StatusCodes.INTERNAL_SERVER_ERROR;
  const isProduction = process.env.NODE_ENV === 'production';

  // ============================================================================
  // CRITICAL SECURITY: Error Sanitization (Fix #11)
  // Production errors should NOT leak implementation details
  // ============================================================================

  // Generic message for production
  const message = isProduction
    ? 'An error occurred while processing your request'
    : err.message || 'Internal Server Error';

  const payload = {
    status: 'error',
    message: message,
  };

  // Only include details in development
  if (!isProduction) {
    payload.stack = err.stack;
    if (err.code) payload.dbCode = err.code;
  }

  // Always log full error server-side for debugging
  logger.error('Error occurred', {
    message: err.message,
    stack: err.stack,
    code: err.code,
    statusCode,
    url: req.originalUrl,
    method: req.method,
    userId: req.user?.id,
    tenantId: req.tenant?.id,
    body: req.body,
    ip: req.ip
  });

  res.status(statusCode).json(payload);
};
