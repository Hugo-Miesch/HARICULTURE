import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { ownedGreenhouse } from '../services/greenhouseAccess.js';
import { AppError } from '../utils/AppError.js';
import { camera } from '../services/camera.js';

const router = Router({ mergeParams: true });
router.use(requireAuth);

router.get(
  '/status',
  asyncHandler(async (req, res) => {
    const greenhouse = await ownedGreenhouse(req.user.id, req.params.greenhouseId);
    res.json({
      camera: {
        enabled: greenhouse.camera.enabled,
        streamUrl: `/api/greenhouses/${greenhouse.id}/camera/stream`
      }
    });
  })
);

router.get(
  '/stream',
  asyncHandler(async (req, res) => {
    const greenhouse = await ownedGreenhouse(req.user.id, req.params.greenhouseId);
    if (!greenhouse.camera.enabled) throw new AppError(503, 'Caméra désactivée');

    try {
      await camera.ensureStarted();
    } catch (error) {
      if (process.env.NODE_ENV !== 'test') console.error('Caméra indisponible:', error);
      throw new AppError(502, 'Flux caméra indisponible');
    }

    res.status(200);
    res.setHeader('Content-Type', 'multipart/x-mixed-replace; boundary=frame');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders();

    const unsubscribe = camera.subscribe((frame) => {
      if (res.writableEnded || res.destroyed) return;
      res.write(`--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${frame.length}\r\n\r\n`);
      res.write(frame);
      res.write('\r\n');
    });
    const close = () => unsubscribe();
    req.once('aborted', close);
    res.once('close', close);
  })
);

export default router;
