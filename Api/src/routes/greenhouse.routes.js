import { Router } from 'express';
import { z } from 'zod';
import { Greenhouse } from '../models/Greenhouse.js';
import { User } from '../models/User.js';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { AppError } from '../utils/AppError.js';
import { ownedGreenhouse } from '../services/greenhouseAccess.js';
import { hardware } from '../services/hardware.js';
import { env } from '../config/env.js';
import { createRateLimit } from '../middleware/rateLimit.js';

const router = Router();
router.use(requireAuth);
const pairingRateLimit = createRateLimit({
  windowMs: env.rateLimitWindowMs,
  max: env.pairingRateLimit,
  key: (req) => `pair:${req.user.id}:${req.ip}`
});

function refreshOnlineState(greenhouse) {
  greenhouse.online =
    Boolean(greenhouse.lastSeenAt) &&
    Date.now() - greenhouse.lastSeenAt.getTime() <= env.greenhouseOfflineAfterMs;
  return greenhouse;
}

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const greenhouses = await Greenhouse.find({ owners: req.user.id }).sort({ createdAt: -1 });
    res.json({ greenhouses: greenhouses.map(refreshOnlineState) });
  })
);

router.post(
  '/pair',
  pairingRateLimit,
  validate(
    z.object({
      body: z.object({
        code: z
          .string()
          .trim()
          .transform((value) => value.toUpperCase())
          .pipe(z.string().regex(/^[A-Z0-9]{4}$/)),
        name: z.string().trim().min(2).max(80).optional()
      }),
      params: z.any(),
      query: z.any()
    })
  ),
  asyncHandler(async (req, res) => {
    const { code, name } = req.validated.body;
    let greenhouse = await Greenhouse.findOne({ pairingCode: code }).select('+pairingCode');
    if (!greenhouse && code === env.defaultGreenhouseCode) {
      greenhouse = await Greenhouse.create({
        name: name || 'Serre de test',
        pairingCode: code,
        owners: [req.user.id],
        online: true,
        lastSeenAt: new Date()
      });
    } else if (!greenhouse) {
      throw new AppError(404, 'Code de serre invalide');
    }

    if (!greenhouse.owners.some((id) => id.equals(req.user.id))) {
      greenhouse.owners.push(req.user.id);
      await greenhouse.save();
    }
    await User.updateOne({ _id: req.user.id }, { $addToSet: { greenhouses: greenhouse.id } });
    greenhouse.pairingCode = undefined;
    res.status(201).json({ greenhouse });
  })
);

router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const greenhouse = await ownedGreenhouse(req.user.id, req.params.id);
    res.json({ greenhouse: refreshOnlineState(greenhouse) });
  })
);

router.post(
  '/:id/heartbeat',
  asyncHandler(async (req, res) => {
    const greenhouse = await ownedGreenhouse(req.user.id, req.params.id);
    greenhouse.online = true;
    greenhouse.lastSeenAt = new Date();
    await greenhouse.save();
    res.json({ online: true, lastSeenAt: greenhouse.lastSeenAt });
  })
);

router.patch(
  '/:id/actuators/:actuator',
  validate(
    z.object({
      body: z.object({
        state: z.boolean(),
        value: z.number().min(0).max(100).optional()
      }),
      params: z.object({
        id: z.string(),
        actuator: z.enum(['light', 'irrigation', 'ventilation'])
      }),
      query: z.any()
    })
  ),
  asyncHandler(async (req, res) => {
    const { id, actuator } = req.validated.params;
    const greenhouse = await ownedGreenhouse(req.user.id, id);
    const state = req.validated.body.state;
    const value = state ? (req.validated.body.value ?? 100) : 0;
    const result = await hardware.setActuator(id, actuator, state, value);
    greenhouse.actuators[actuator] = { state, value, updatedAt: new Date() };
    await greenhouse.save();
    res.json({ actuator: greenhouse.actuators[actuator], hardware: result });
  })
);

export default router;
