import bcrypt from 'bcryptjs';
import { pool } from '../config/db.js';

export const findUserByEmail = async (email) => {
  const { rows } = await pool.query(
    'SELECT id, username, email, password_hash, role, is_active FROM users WHERE email = $1',
    [email]
  );
  return rows[0] || null;
};

export const createUser = async ({ username, email, password, firstName, lastName, role }) => {
  const passwordHash = await bcrypt.hash(password, 10);

  const { rows } = await pool.query(
    `INSERT INTO users (username, email, password_hash, first_name, last_name, role)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id, username, email, role, is_active, created_at`,
    [username, email, passwordHash, firstName, lastName, role]
  );

  return rows[0];
};

export const verifyPassword = async (plain, hash) => {
  return bcrypt.compare(plain, hash);
};
