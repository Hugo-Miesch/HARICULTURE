import { User } from '../models/User.js';
import { AppError } from '../utils/AppError.js';
import { verifyToken } from '../utils/jwt.js';
import { asyncHandler } from '../utils/asyncHandler.js';

export const requireAuth = asyncHandler(async (req, _res, next) => {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) throw new AppError(401, 'Authentification requise');

  let payload;
  try {
    payload = verifyToken(token);
  } catch {
    throw new AppError(401, 'Jeton invalide ou expiré');
  }

  const user = await User.findById(payload.sub);
  if (!user) throw new AppError(401, 'Utilisateur introuvable');
  req.user = user;
  next();
});
