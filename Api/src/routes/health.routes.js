import { Router } from 'express';
import mongoose from 'mongoose';

const router = Router();
router.get('/', (_req, res) => {
  const database = mongoose.connection.readyState === 1 ? 'connected' : 'disconnected';
  res.status(database === 'connected' ? 200 : 503).json({
    status: database === 'connected' ? 'ok' : 'degraded',
    database,
    timestamp: new Date().toISOString()
  });
});

export default router;
