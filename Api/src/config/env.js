import 'dotenv/config';

const isTest = process.env.NODE_ENV === 'test';

export const env = {
  nodeEnv: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 3000),
  mongoUri: process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/hariculture',
  jwtSecret: process.env.JWT_SECRET || (isTest ? 'test-secret-at-least-32-characters-long' : ''),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',
  corsOrigin: process.env.CORS_ORIGIN || '*',
  defaultGreenhouseCode: process.env.DEFAULT_GREENHOUSE_CODE || '0000',
  cameraStreamUrl: process.env.CAMERA_STREAM_URL || 'http://127.0.0.1:8080/stream',
  hardwareMode: process.env.HARDWARE_MODE || 'mock'
};

if (!env.jwtSecret) {
  throw new Error('JWT_SECRET doit être défini dans le fichier .env');
}
