import { StatusCodes } from 'http-status-codes';
import supabase from '../config/supabase.js';

export const requireAuth = async (req, res, next) => {
  try {
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      return res.status(StatusCodes.UNAUTHORIZED).json({
        status: 'error',
        message: 'Missing or invalid Authorization header',
      });
    }

    const token = header.slice('Bearer '.length);

    // Verify token with Supabase
    const { data: { user }, error } = await supabase.auth.getUser(token);

    if (error || !user) {
      console.error(`[AUTH] Verification failed for token: ${token.substring(0, 10)}... Error:`, error?.message || 'No user found');
      return res.status(StatusCodes.UNAUTHORIZED).json({
        status: 'error',
        message: 'Invalid or expired token',
      });
    }

    // Fetch user profile (role, branch, etc)
    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single();

    if (profileError || !profile) {
      console.warn(`Auth Middleware: Profile not found for user ${user.id} (${user.email}). Error:`, profileError);
      return res.status(StatusCodes.FORBIDDEN).json({
        status: 'error',
        message: 'User profile not found. Please contact administrator.',
      });
    }

    // Attach to request
    req.user = {
      id: user.id,
      email: user.email,
      role: profile.role,
      tenant_id: profile.tenant_id,
      branch_id: profile.branch_id,
      full_name: profile.full_name
    };

    console.log(`[AUTH] User: ${user.email} | Role: ${profile.role} | Path: ${req.originalUrl}`);

    next();
  } catch (err) {
    console.error('Auth Middleware Error:', err);
    return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Authentication failed',
    });
  }
};
