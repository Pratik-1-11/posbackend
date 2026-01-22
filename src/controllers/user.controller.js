import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';
import { scopeToTenant, addTenantToPayload, ensureTenantOwnership } from '../utils/tenantQuery.js';

export const getUsers = async (req, res, next) => {
  try {
    let query = supabase
      .from('profiles')
      .select('*, branches(name)')
      .order('created_at', { ascending: false });

    query = scopeToTenant(query, req, 'profiles');

    const { data: users, error } = await query;

    if (error) throw error;

    res.status(StatusCodes.OK).json({
      status: 'success',
      results: users.length,
      data: { users },
    });
  } catch (err) {
    next(err);
  }
};

export const createUser = async (req, res, next) => {
  try {
    const { email, password, fullName, username, role, branchId } = req.body;

    // ============================================================================
    // CRITICAL SECURITY: Role Hierarchy Validation (Fix #7)
    // Prevents cashiers from creating SUPER_ADMIN accounts
    // ============================================================================

    const allowedRoles = {
      'SUPER_ADMIN': ['SUPER_ADMIN', 'VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER', 'INVENTORY_MANAGER', 'admin', 'manager', 'cashier', 'waiter'],
      'VENDOR_ADMIN': ['VENDOR_ADMIN', 'VENDOR_MANAGER', 'CASHIER', 'INVENTORY_MANAGER', 'admin', 'manager', 'cashier', 'waiter'],
      'VENDOR_MANAGER': ['CASHIER', 'INVENTORY_MANAGER', 'manager', 'cashier', 'waiter'],
      'admin': ['VENDOR_MANAGER', 'CASHIER', 'INVENTORY_MANAGER', 'manager', 'cashier', 'waiter'],
      'manager': ['CASHIER', 'cashier', 'waiter']
    };

    const userRole = req.user.role;
    const canCreateRoles = allowedRoles[userRole] || [];

    if (!canCreateRoles.includes(role)) {
      return res.status(StatusCodes.FORBIDDEN).json({
        status: 'error',
        message: `Access denied: Your role (${userRole}) cannot create users with role: ${role}. You can only create: ${canCreateRoles.join(', ')}`
      });
    }

    // Validate email
    if (!email || !email.includes('@')) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Valid email is required'
      });
    }

    // Validate password
    if (!password || password.length < 8) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Password must be at least 8 characters long'
      });
    }

    // 1. Create Auth User using Admin API
    const { data: authUser, error: authError } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: fullName,
        tenant_id: req.tenant.id // Store tenant_id in metadata for recovery
      }
    });

    if (authError) throw authError;

    // 2. Profile creation (Manual injection of tenant_id)
    const profilePayload = addTenantToPayload({
      id: authUser.user.id,
      full_name: fullName,
      username: username,
      role: role,
      email: email,
      branch_id: branchId || req.user.branch_id
    }, req);

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .upsert(profilePayload)
      .select()
      .single();

    if (profileError) {
      // Cleanup auth user if profile creation fails?
      await supabase.auth.admin.deleteUser(authUser.user.id);
      throw profileError;
    }

    res.status(StatusCodes.CREATED).json({
      status: 'success',
      data: { user: profile },
    });
  } catch (err) {
    next(err);
  }
};

export const updateUser = async (req, res, next) => {
  try {
    const { id } = req.params;

    // Ensure ownership before updating
    await ensureTenantOwnership(supabase, req, 'profiles', id);

    const { fullName, username, role, branchId, email, password } = req.body;

    // 1. Update Profile
    const updateData = {};
    if (fullName) updateData.full_name = fullName;
    if (username) updateData.username = username;
    if (role) updateData.role = role;
    if (branchId) updateData.branch_id = branchId;
    if (email) updateData.email = email;

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .update(updateData)
      .eq('id', id)
      .select()
      .single();

    if (profileError) throw profileError;

    // 2. Update Auth (if email or password provided)
    if (email || password) {
      const authUpdate = {};
      if (email) authUpdate.email = email;
      if (password) authUpdate.password = password;

      const { error: authError } = await supabase.auth.admin.updateUserById(id, authUpdate);
      if (authError) throw authError;
    }

    res.status(StatusCodes.OK).json({
      status: 'success',
      data: { user: profile },
    });
  } catch (err) {
    next(err);
  }
};

export const deleteUser = async (req, res, next) => {
  try {
    const { id } = req.params;

    // Don't allow deleting self
    if (id === req.user.id) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'You cannot delete your own account.'
      });
    }

    // Ensure ownership before deleting
    await ensureTenantOwnership(supabase, req, 'profiles', id);

    // Delete Auth User (cascade will delete profile)
    const { error: authError } = await supabase.auth.admin.deleteUser(id);
    if (authError) throw authError;

    res.status(StatusCodes.OK).json({
      status: 'success',
      message: 'User deleted successfully'
    });
  } catch (err) {
    next(err);
  }
};

