import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';

export const login = async (req, res, next) => {
  try {
    const { email, password } = req.body;

    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      return res.status(StatusCodes.UNAUTHORIZED).json({
        status: 'error',
        message: error.message,
      });
    }

    const { session, user } = data;

    // Fetch profile and tenant to return role info
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('*, tenants!tenant_id(*)')
      .eq('id', user.id)
      .single();

    if (profileError) {
      console.error(`[Auth] Profile lookup failed for user ${user.id}:`, profileError.message);
      // We still allow login but with minimal role if profile is missing 
      // (though frontend might reject it)
    }

    const userRole = profile?.role || 'user';
    console.log(`[Auth] User logged in: ${user.email} | Role: ${userRole} | ID: ${user.id}`);

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
    const { email, password, full_name, role, branch_id } = req.body;

    // 1. Create Auth User
    const { data, error } = await supabase.auth.signUp({
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
        message: 'Registration failed',
      });
    }

    // 2. Create Profile (Using service role or ensure public insert is allowed, 
    // but here we act as backend so we should ideally use service role key for admin tasks. 
    // However, for this MVP we use the client. 
    // If RLS prevents insert, we might fail here. 
    // Assuming 'profiles' RLS allows insert for authenticated user matching ID, 
    // OR we simply rely on the user to insert their profile? 
    // BETTER: The backend should use SERVICE_ROLE key for administrative tasks like creating other users.
    // But we only have ANON key configured in src/config/supabase.js currently.
    // For now, let's attempt insert. If it fails, we'll need SERVICE_KEY.)

    // 2. Create Profile
    const { error: profileError } = await supabase
      .from('profiles')
      .insert({
        id: data.user.id,
        email: email, // ensure email is synced
        username: email.split('@')[0],
        full_name: full_name,
        role: role || 'cashier',
        tenant_id: req.body.tenant_id || '00000000-0000-0000-0000-000000000002', // fallback for migration
        branch_id: (branch_id && branch_id !== '') ? branch_id : null
      });

    if (profileError) {
      // cleanup auth user if profile fails? 
      // For now just warn.
      console.error('Profile creation failed:', profileError);
      return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
        status: 'error',
        message: 'User created but profile creation failed. ' + profileError.message
      });
    }

    return res.status(StatusCodes.CREATED).json({
      status: 'success',
      data: {
        user: {
          id: data.user.id,
          email: data.user.email,
        },
        message: 'User registered successfully check email for verification if enabled.',
      },
    });
  } catch (err) {
    next(err);
  }
};
export const logout = async (req, res, next) => {
  try {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;

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
    // req.user is populated by requireAuth middleware
    res.status(StatusCodes.OK).json({
      status: 'success',
      data: { user: req.user }
    });
  } catch (err) {
    next(err);
  }
};
