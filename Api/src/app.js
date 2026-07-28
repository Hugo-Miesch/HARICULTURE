import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { env } from './config/env.js';
import authRoutes from './routes/auth.routes.js';
import greenhouseRoutes from './routes/greenhouse.routes.js';
import sensorRoutes from './routes/sensor.routes.js';
import routineRoutes from './routes/routine.routes.js';
import cameraRoutes from './routes/camera.routes.js';
import healthRoutes from './routes/health.routes.js';
import { errorHandler, notFound } from './middleware/errorHandler.js';

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.use(helmet({ crossOriginResourcePolicy: false }));
  app.use(cors({ origin: env.corsOrigin === '*' ? true : env.corsOrigin.split(',') }));
  app.use(express.json({ limit: '256kb' }));
  if (env.nodeEnv !== 'test') app.use(morgan('combined'));

  app.use('/api/health', healthRoutes);
  app.use('/api/auth', authRoutes);
  app.use('/api/greenhouses', greenhouseRoutes);
  app.use('/api/greenhouses/:greenhouseId/sensors', sensorRoutes);
  app.use('/api/greenhouses/:greenhouseId/routines', routineRoutes);
  app.use('/api/greenhouses/:greenhouseId/camera', cameraRoutes);

  app.use(notFound);
  app.use(errorHandler);
  return app;
}
