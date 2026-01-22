/**
 * Authorization Middleware
 * 
 * Role-based access control middleware for multi-tenant POS system.
 */

/**
 * Require specific roles to access a route
 * @param {string[]} allowedRoles - Array of allowed role names
 * @returns {Function} Express middleware function
 */
export function requireRole(allowedRoles) {
    return (req, res, next) => {
        if (!req.userRole) {
            return res.status(403).json({
                error: 'Forbidden',
                message: 'Role information missing. Please re-authenticate.'
            });
        }

        if (!allowedRoles.includes(req.userRole)) {
            return res.status(403).json({
                error: 'Insufficient permissions',
                message: `This action requires one of the following roles: ${allowedRoles.join(', ')}`,
                required: allowedRoles,
                current: req.userRole
            });
        }

        next();
    };
}

/**
 * Require Super Admin role
 * Platform owner only
 */
export function requireSuperAdmin(req, res, next) {
    if (req.userRole !== 'SUPER_ADMIN') {
        return res.status(403).json({
            error: 'Forbidden',
            message: 'This action requires Super Admin privileges'
        });
    }

    next();
}

/**
 * Require Vendor Admin role (within their tenant)
 * Vendor owners can manage their own business
 */
export function requireVendorAdmin(req, res, next) {
    if (!['SUPER_ADMIN', 'VENDOR_ADMIN'].includes(req.userRole)) {
        return res.status(403).json({
            error: 'Forbidden',
            message: 'This action requires Admin privileges'
        });
    }

    next();
}

/**
 * Require Manager or above
 * For operations like viewing reports
 */
export function requireManager(req, res, next) {
    const managerRoles = ['SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER'];

    if (!managerRoles.includes(req.userRole)) {
        return res.status(403).json({
            error: 'Forbidden',
            message: 'This action requires Manager or Admin privileges'
        });
    }

    next();
}

/**
 * Check if user can manage products
 * Inventory managers, managers, and admins
 */
export function canManageProducts(req, res, next) {
    const allowedRoles = [
        'SUPER_ADMIN',
        'VENDOR_ADMIN',
        'VENDOR_MANAGER',
        'INVENTORY_MANAGER'
    ];

    if (!allowedRoles.includes(req.userRole)) {
        return res.status(403).json({
            error: 'Forbidden',
            message: 'You do not have permission to manage products'
        });
    }

    next();
}

/**
 * Check if user can create sales
 * Cashiers and above
 */
export function canCreateSales(req, res, next) {
    const allowedRoles = [
        'SUPER_ADMIN',
        'VENDOR_ADMIN',
        'VENDOR_MANAGER',
        'CASHIER'
    ];

    if (!allowedRoles.includes(req.userRole)) {
        return res.status(403).json({
            error: 'Forbidden',
            message: 'You do not have permission to create sales'
        });
    }

    next();
}

/**
 * Check if user can view reports
 * Managers and admins only
 */
export function canViewReports(req, res, next) {
    const allowedRoles = [
        'SUPER_ADMIN',
        'VENDOR_ADMIN',
        'VENDOR_MANAGER'
    ];

    if (!allowedRoles.includes(req.userRole)) {
        return res.status(403).json({
            error: 'Forbidden',
            message: 'You do not have permission to view reports'
        });
    }

    next();
}

/**
 * Check subscription tier for premium features
 * @param {string[]} allowedTiers - Array of allowed subscription tiers
 */
export function requireSubscriptionTier(allowedTiers) {
    return (req, res, next) => {
        if (!req.tenant?.tier) {
            return res.status(403).json({
                error: 'Forbidden',
                message: 'Subscription information not available'
            });
        }

        if (!allowedTiers.includes(req.tenant.tier)) {
            return res.status(403).json({
                error: 'Upgrade required',
                message: `This feature requires one of the following plans: ${allowedTiers.join(', ')}`,
                currentPlan: req.tenant.tier,
                requiredPlans: allowedTiers
            });
        }

        next();
    };
}

/**
 * Role hierarchy mapping
 */
export const ROLE_HIERARCHY = {
    'SUPER_ADMIN': 5,
    'VENDOR_ADMIN': 4,
    'VENDOR_MANAGER': 3,
    'INVENTORY_MANAGER': 2,
    'CASHIER': 1
};

/**
 * Check if user has minimum role level
 * @param {string} minimumRole - Minimum required role
 */
export function requireMinimumRole(minimumRole) {
    return (req, res, next) => {
        const userLevel = ROLE_HIERARCHY[req.userRole] || 0;
        const requiredLevel = ROLE_HIERARCHY[minimumRole] || 0;

        if (userLevel < requiredLevel) {
            return res.status(403).json({
                error: 'Insufficient permissions',
                message: `This action requires ${minimumRole} role or higher`,
                currentRole: req.userRole
            });
        }

        next();
    };
}
