import { StatusCodes } from 'http-status-codes';
import { supabaseAuth, supabaseAdmin } from '../config/supabase.js';

export const login = async (req, res, next) => {
  try {
    const { email, password } = req.body;

    // Use ANON key client for signInWithPassword — required to get a real user session
    const { data, error } = await supabaseAuth.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      console.error(`[Auth] Login failed for ${email}:`, error.message);
      return res.status(StatusCodes.UNAUTHORIZED).json({
        status: 'error',
        message: error.message,
      });
    }

    const { session, user } = data;

    // Use SERVICE ROLE client for profile lookup — bypasses RLS
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('*, tenants!tenant_id(*)')
      .eq('id', user.id)
      .single();

    if (profileError) {
      console.error(`[Auth] Profile lookup failed for user ${user.id}:`, profileError.message);
      return res.status(StatusCodes.FORBIDDEN).json({
        status: 'error',
        message: `Profile not found for this user. Please contact the administrator. (${profileError.message})`,
      });
    }

    const userRole = profile?.role || null;
    if (!userRole) {
      return res.status(StatusCodes.FORBIDDEN).json({
        status: 'error',
        message: 'User role is not assigned. Please contact the administrator.',
      });
    }

    console.log(`[Auth] ✅ Login success: ${user.email} | Role: ${userRole} | ID: ${user.id}`);

    return res.status(StatusCodes.OK).json({
      status: 'success',
      data: {
        accessToken: session.access_token,
        refreshToken: session.refresh_token,
        user: {
          id: user.id,
          email: user.email,
          role: userRole,
          full_name: profile?.full_name,
          branch_id: profile?.branch_id || null,
          tenant: profile?.tenants ? {
            id: profile.tenants.id,
            name: profile.tenants.name,
            subscription_status: profile.tenants.subscription_status,
            subscription_end_date: profile.tenants.subscription_end_date,
            plan_interval: profile.tenants.plan_interval
          } : null
        },
      },
    });
  } catch (err) {
    next(err);
  }
};

export const register = async (req, res, next) => {
  try {
    const { email, password, full_name, role, branch_id, tenant_id } = req.body;

    // Use ANON key for sign up
    const { data, error } = await supabaseAuth.auth.signUp({
      email,
      password,
    });

    if (error) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: error.message,
      });
    }

    if (!data.user) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Registration failed — no user returned from Supabase.',
      });
    }

    // Use SERVICE ROLE for inserting the profile (bypasses RLS)
    const { error: profileError } = await supabaseAdmin
      .from('profiles')
      .insert({
        id: data.user.id,
        email: email,
        username: email.split('@')[0],
        full_name: full_name,
        role: role || 'CASHIER',
        tenant_id: tenant_id || null,
        branch_id: (branch_id && branch_id !== '') ? branch_id : null
      });

    if (profileError) {
      console.error('Profile creation failed:', profileError);
      return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
        status: 'error',
        message: 'User created but profile creation failed: ' + profileError.message
      });
    }

    return res.status(StatusCodes.CREATED).json({
      status: 'success',
      data: {
        user: {
          id: data.user.id,
          email: data.user.email,
        },
        message: 'User registered successfully.',
      },
    });
  } catch (err) {
    next(err);
  }
};

export const logout = async (req, res, next) => {
  try {
    await supabaseAuth.auth.signOut();
    return res.status(StatusCodes.OK).json({
      status: 'success',
      message: 'Logged out successfully'
    });
  } catch (err) {
    next(err);
  }
};

export const getCurrentUser = async (req, res, next) => {
  try {
    res.status(StatusCodes.OK).json({
      status: 'success',
      data: { user: req.user }
    });
  } catch (err) {
    next(err);
  }
};
