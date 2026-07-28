import { Router } from 'express';
import mongoose from 'mongoose';

const router = Router();
router.get('/', async (_req, res) => {
  try {
    if (mongoose.connection.readyState !== 1) throw new Error('MongoDB déconnecté');
    await mongoose.connection.db.admin().ping();
    res.json({
      status: 'ok',
      database: 'connected',
      timestamp: new Date().toISOString()
    });
  } catch {
    res.status(503).json({
      status: 'degraded',
      database: 'unavailable',
      timestamp: new Date().toISOString()
    });
  }
});

export default router;
