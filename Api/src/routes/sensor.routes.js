import { Router } from 'express';
import { z } from 'zod';
import { SensorReading } from '../models/SensorReading.js';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { ownedGreenhouse } from '../services/greenhouseAccess.js';
import { hardware } from '../services/hardware.js';

const router = Router({ mergeParams: true });
router.use(requireAuth);

const readingBody = z.object({
  temperature: z.number().min(-50).max(100).optional(),
  airHumidity: z.number().min(0).max(100).optional(),
  soilHumidity: z.number().min(0).max(100).optional(),
  lightLevel: z.number().min(0).optional(),
  measuredAt: z.coerce.date().optional()
});

router.post(
  '/',
  validate(z.object({ body: readingBody, params: z.object({ greenhouseId: z.string() }), query: z.any() })),
  asyncHandler(async (req, res) => {
    await ownedGreenhouse(req.user.id, req.params.greenhouseId);
    const reading = await SensorReading.create({
      greenhouse: req.params.greenhouseId,
      ...req.validated.body
    });
    res.status(201).json({ reading });
  })
);

router.post(
  '/collect',
  asyncHandler(async (req, res) => {
    await ownedGreenhouse(req.user.id, req.params.greenhouseId);
    const values = await hardware.readSensors(req.params.greenhouseId);
    const reading = await SensorReading.create({
      greenhouse: req.params.greenhouseId,
      ...values
    });
    res.status(201).json({ reading });
  })
);

router.get(
  '/',
  validate(
    z.object({
      body: z.any(),
      params: z.object({ greenhouseId: z.string() }),
      query: z.object({ limit: z.coerce.number().int().min(1).max(500).default(100) })
    })
  ),
  asyncHandler(async (req, res) => {
    await ownedGreenhouse(req.user.id, req.params.greenhouseId);
    const readings = await SensorReading.find({ greenhouse: req.params.greenhouseId })
      .sort({ measuredAt: -1 })
      .limit(req.validated.query.limit);
    res.json({ readings });
  })
);

router.get(
  '/latest',
  asyncHandler(async (req, res) => {
    await ownedGreenhouse(req.user.id, req.params.greenhouseId);
    const reading = await SensorReading.findOne({ greenhouse: req.params.greenhouseId }).sort({
      measuredAt: -1
    });
    res.json({ reading });
  })
);

export default router;
