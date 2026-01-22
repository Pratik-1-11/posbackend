import { StatusCodes } from 'http-status-codes';
import { users } from '../data/staticData.js';

// Get all users (admin only)
export const getUsers = async (req, res) => {
  try {
    // Return users without passwords
    const usersWithoutPasswords = users.map(({ password, ...user }) => user);

    res.status(StatusCodes.OK).json({
      status: 'success',
      data: {
        users: usersWithoutPasswords,
        count: usersWithoutPasswords.length
      }
    });
  } catch (error) {
    res.status(StatusCodes.INTERNAL_SERVER_ERROR).json({
      status: 'error',
      message: 'Failed to fetch users'
    });
  }
};
