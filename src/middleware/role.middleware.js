import { StatusCodes } from 'http-status-codes';

export const requireRole = (...roles) => {
  return (req, res, next) => {
    // 1. Check if user is authenticated
    if (!req.user) {
      return res.status(StatusCodes.UNAUTHORIZED).json({
        status: 'error',
        message: 'Authentication required',
      });
    }

    // 2. Normalize user role and allowed roles
    const userRoleRaw = req.user.role;
    const userRole = (userRoleRaw || '').toString().trim().toUpperCase();

    // Normalize allowed roles to UPPERCASE
    const allowedRoles = roles.map(r => r.toString().trim().toUpperCase());

    // 3. Check for match
    // Support if user has multiple roles (future proofing) or single role
    const hasRole = Array.isArray(userRoleRaw)
      ? userRoleRaw.some(r => allowedRoles.includes(r.toUpperCase()))
      : allowedRoles.includes(userRole);

    if (!hasRole) {
      console.warn(`[Auth] Limit Access: User Role [${userRole}] not in Allowed [${allowedRoles.join(', ')}]`);
      return res.status(StatusCodes.FORBIDDEN).json({
        status: 'error',
        message: `Insufficient permissions. Access denied for role: ${userRoleRaw}`,
      });
    }

    next();
  };
};
