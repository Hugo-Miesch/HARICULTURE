import { Router } from 'express';
import { z } from 'zod';
import { User } from '../models/User.js';
import { validate } from '../middleware/validate.js';
import { requireAuth } from '../middleware/auth.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { AppError } from '../utils/AppError.js';
import { signToken } from '../utils/jwt.js';

const router = Router();
const credentials = z.object({
  body: z.object({
    email: z.email().transform((value) => value.toLowerCase()),
    password: z.string().min(8).max(128)
  }),
  params: z.any(),
  query: z.any()
});

router.post(
  '/register',
  validate(
    credentials.extend({
      body: credentials.shape.body.extend({ name: z.string().trim().min(2).max(80) })
    })
  ),
  asyncHandler(async (req, res) => {
    const { name, email, password } = req.validated.body;
    if (await User.exists({ email })) throw new AppError(409, 'Cet email est déjà utilisé');
    const passwordHash = await User.hashPassword(password);
    const user = await User.create({ name, email, passwordHash });
    res.status(201).json({ token: signToken(user.id), user });
  })
);

router.post(
  '/login',
  validate(credentials),
  asyncHandler(async (req, res) => {
    const { email, password } = req.validated.body;
    const user = await User.findOne({ email }).select('+passwordHash');
    if (!user || !(await user.verifyPassword(password))) {
      throw new AppError(401, 'Email ou mot de passe incorrect');
    }
    user.passwordHash = undefined;
    res.json({ token: signToken(user.id), user });
  })
);

router.get('/me', requireAuth, (req, res) => res.json({ user: req.user }));

export default router;
