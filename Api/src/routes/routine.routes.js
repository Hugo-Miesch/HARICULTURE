import { Router } from 'express';
import { z } from 'zod';
import { Routine } from '../models/Routine.js';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { AppError } from '../utils/AppError.js';
import { ownedGreenhouse } from '../services/greenhouseAccess.js';

const router = Router({ mergeParams: true });
router.use(requireAuth);

const routineFields = {
  name: z.string().trim().min(2).max(80),
  actuator: z.enum(['light', 'irrigation', 'ventilation']),
  enabled: z.boolean().optional(),
  time: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
  days: z.array(z.number().int().min(0).max(6)).min(1),
  durationSeconds: z.number().int().min(1).max(86400),
  value: z.number().min(0).max(100).optional()
};

router.get(
  '/',
  asyncHandler(async (req, res) => {
    await ownedGreenhouse(req.user.id, req.params.greenhouseId);
    const routines = await Routine.find({ greenhouse: req.params.greenhouseId }).sort({ time: 1 });
    res.json({ routines });
  })
);

router.post(
  '/',
  validate(
    z.object({
      body: z.object(routineFields),
      params: z.object({ greenhouseId: z.string() }),
      query: z.any()
    })
  ),
  asyncHandler(async (req, res) => {
    await ownedGreenhouse(req.user.id, req.params.greenhouseId);
    const routine = await Routine.create({
      greenhouse: req.params.greenhouseId,
      ...req.validated.body
    });
    res.status(201).json({ routine });
  })
);

router.patch(
  '/:routineId',
  validate(
    z.object({
      body: z.object(routineFields).partial().refine((value) => Object.keys(value).length > 0),
      params: z.object({ greenhouseId: z.string(), routineId: z.string() }),
      query: z.any()
    })
  ),
  asyncHandler(async (req, res) => {
    await ownedGreenhouse(req.user.id, req.params.greenhouseId);
    const routine = await Routine.findOneAndUpdate(
      { _id: req.params.routineId, greenhouse: req.params.greenhouseId },
      req.validated.body,
      { new: true, runValidators: true }
    );
    if (!routine) throw new AppError(404, 'Routine introuvable');
    res.json({ routine });
  })
);

router.delete(
  '/:routineId',
  asyncHandler(async (req, res) => {
    await ownedGreenhouse(req.user.id, req.params.greenhouseId);
    const routine = await Routine.findOneAndDelete({
      _id: req.params.routineId,
      greenhouse: req.params.greenhouseId
    });
    if (!routine) throw new AppError(404, 'Routine introuvable');
    res.status(204).end();
  })
);

export default router;
