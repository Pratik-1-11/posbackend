import { pool } from '../config/db.js';

export const listUsers = async () => {
  const { rows } = await pool.query(
    `SELECT id,
            username,
            email,
            first_name AS "firstName",
            last_name AS "lastName",
            role,
            is_active AS "isActive",
            last_login AS "lastLogin",
            created_at AS "createdAt"
     FROM users
     ORDER BY created_at DESC`
  );

  return rows;
};
