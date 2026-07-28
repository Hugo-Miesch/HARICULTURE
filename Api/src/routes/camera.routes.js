import { Router } from 'express';
import { Readable } from 'node:stream';
import { requireAuth } from '../middleware/auth.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { ownedGreenhouse } from '../services/greenhouseAccess.js';
import { env } from '../config/env.js';
import { AppError } from '../utils/AppError.js';

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

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    let upstream;
    try {
      upstream = await fetch(env.cameraStreamUrl, { signal: controller.signal });
    } catch {
      clearTimeout(timeout);
      throw new AppError(502, 'Flux caméra indisponible');
    }
    clearTimeout(timeout);
    if (!upstream.ok || !upstream.body) {
      controller.abort();
      throw new AppError(502, 'Flux caméra indisponible');
    }

    const stream = Readable.fromWeb(upstream.body);
    const closeUpstream = () => {
      controller.abort();
      stream.destroy();
    };
    req.once('aborted', closeUpstream);
    res.once('close', closeUpstream);
    res.status(200);
    res.setHeader(
      'Content-Type',
      upstream.headers.get('content-type') || 'multipart/x-mixed-replace; boundary=frame'
    );
    res.setHeader('Cache-Control', 'no-store');
    stream.pipe(res);
  })
);

export default router;
