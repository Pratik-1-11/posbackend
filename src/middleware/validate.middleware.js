import { StatusCodes } from 'http-status-codes';

export const validate = (schema) => {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.body, {
      abortEarly: false,
      stripUnknown: true,
    });

    if (error) {
      console.error('Validation error details:', error.details);
      const firstError = error.details[0]?.message || 'Validation error';
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: firstError,
        errors: error.details.map((d) => d.message),
      });
    }

    req.body = value;
    next();
  };
};
