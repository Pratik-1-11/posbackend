import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import bcrypt from 'bcryptjs';

const SALT_ROUNDS = 10;

export const verifyManagerAuth = async (req, res, next) => {
    try {
        const { pin } = req.body;
        const tenantId = req.tenant.id;

        if (!pin) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'PIN is required'
            });
        }

        // Find all managers/admins in this tenant and check their PINs
        // In a real system, you might ask for a specific manager's username/ID too, 
        // but often in POS, any manager can swipe their card or enter a PIN.
        const { data: managers, error } = await supabase
            .from('profiles')
            .select('id, manager_pin_hash, role, full_name')
            .eq('tenant_id', tenantId)
            .in('role', ['VENDOR_ADMIN', 'VENDOR_MANAGER']);

        if (error) throw error;

        let authorizedManager = null;

        for (const manager of managers) {
            if (manager.manager_pin_hash) {
                const isValid = await bcrypt.compare(pin, manager.manager_pin_hash);
                if (isValid) {
                    authorizedManager = manager;
                    break;
                }
            }
        }

        if (!authorizedManager) {
            return res.status(StatusCodes.UNAUTHORIZED).json({
                status: 'error',
                message: 'Invalid manager PIN'
            });
        }

        return res.status(StatusCodes.OK).json({
            status: 'success',
            data: {
                manager: {
                    id: authorizedManager.id,
                    name: authorizedManager.full_name,
                    role: authorizedManager.role
                }
            }
        });
    } catch (err) {
        next(err);
    }
};

export const updateManagerPin = async (req, res, next) => {
    try {
        const { userId, newPin } = req.body;
        const tenantId = req.tenant.id;

        // Security: Only Vendor Admin can change other people's PINs
        // Or users can change their own if they have manager/admin role
        const isSelf = req.user.id === userId;
        const isAdmin = req.user.role === 'VENDOR_ADMIN';

        if (!isSelf && !isAdmin) {
            return res.status(StatusCodes.FORBIDDEN).json({
                status: 'error',
                message: 'Unauthorized to update this PIN'
            });
        }

        if (!newPin || newPin.length < 4) {
            return res.status(StatusCodes.BAD_REQUEST).json({
                status: 'error',
                message: 'PIN must be at least 4 digits'
            });
        }

        const hashedPin = await bcrypt.hash(newPin, SALT_ROUNDS);

        const { error } = await supabase
            .from('profiles')
            .update({ manager_pin_hash: hashedPin })
            .eq('id', userId)
            .eq('tenant_id', tenantId);

        if (error) throw error;

        return res.status(StatusCodes.OK).json({
            status: 'success',
            message: 'Manager PIN updated successfully'
        });
    } catch (err) {
        next(err);
    }
};
