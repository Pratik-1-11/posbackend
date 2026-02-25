import { StatusCodes } from 'http-status-codes';
import { supabaseAdmin } from '../config/supabase.js';

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

    // Verify token with Supabase admin client
    const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);

    if (error || !user) {
      console.error(`[AUTH] Token verification failed: ${error?.message || 'No user found'}`);
      return res.status(StatusCodes.UNAUTHORIZED).json({
        status: 'error',
        message: 'Invalid or expired token',
      });
    }

    // Fetch user profile using service role (bypasses RLS)
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single();

    if (profileError || !profile) {
      console.warn(`[AUTH] Profile not found for user ${user.id} (${user.email}):`, profileError?.message);
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

    console.log(`[AUTH] ✅ ${user.email} | Role: ${profile.role} | ${req.method} ${req.originalUrl}`);
    next();
  } catch (err) {
    console.error('[AUTH] Middleware error:', err);
    return res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Authentication failed',
    });
  }
};
