import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { StatusCodes } from 'http-status-codes';
import { users } from '../data/staticData.js';
import { config } from '../config/env.js';

// JWT token generation
const generateToken = (user) => {
  return jwt.sign(
    { id: user.id, username: user.username, role: user.role },
    config.jwt.secret,
    { expiresIn: config.jwt.expiresIn }
  );
};

// Login with static data
export const login = async (req, res) => {
  try {
    const { username, password } = req.body;

    // Find user in static data
    const user = users.find(u => u.username === username);
    if (!user) {
      return res.status(StatusCodes.UNAUTHORIZED).json({
        status: 'error',
        message: 'Invalid credentials'
      });
    }

    // Check password
    const isPasswordValid = await bcrypt.compare(password, user.password);
    if (!isPasswordValid) {
      return res.status(StatusCodes.UNAUTHORIZED).json({
        status: 'error',
        message: 'Invalid credentials'
      });
    }

    // Generate token
    const token = generateToken(user);

    // Return user data without password
    const { password: _, ...userWithoutPassword } = user;

    res.status(StatusCodes.OK).json({
      status: 'success',
      data: {
        user: userWithoutPassword,
        token
      }
    });
  } catch (error) {
    res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Login failed'
    });
  }
};

// Register with static data (for admin only)
export const register = async (req, res) => {
  try {
    const { username, email, password, role = 'CASHIER' } = req.body;

    // Check if user already exists
    const existingUser = users.find(u => u.username === username || u.email === email);
    if (existingUser) {
      return res.status(StatusCodes.BAD_REQUEST).json({
        status: 'error',
        message: 'Username or email already exists'
      });
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(password, 10);

    // Create new user (in real implementation, this would add to the static array)
    const newUser = {
      id: users.length + 1,
      username,
      email,
      password: hashedPassword,
      role,
      createdAt: new Date(),
      updatedAt: new Date()
    };

    // For static data, we'll just return success without actually modifying the array
    const { password: _, ...userWithoutPassword } = newUser;

    res.status(StatusCodes.CREATED).json({
      status: 'success',
      data: {
        user: userWithoutPassword
      }
    });
  } catch (error) {
    res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Registration failed'
    });
  }
};
