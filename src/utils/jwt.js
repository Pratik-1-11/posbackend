import jwt from 'jsonwebtoken';
import { config } from '../config/env.js';

export const signAccessToken = ({ userId, role }) => {
  return jwt.sign({ userId, role }, config.jwt.secret, { expiresIn: config.jwt.expiresIn });
};

export const verifyAccessToken = (token) => {
  return jwt.verify(token, config.jwt.secret);
};
