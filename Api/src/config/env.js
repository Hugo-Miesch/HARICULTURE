import 'dotenv/config';
import { fileURLToPath } from 'node:url';

const isTest = process.env.NODE_ENV === 'test';

export const env = {
  nodeEnv: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT || 3000),
  mongoUri: process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/hariculture',
  jwtSecret: process.env.JWT_SECRET || (isTest ? 'test-secret-at-least-32-characters-long' : ''),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',
  corsOrigin: process.env.CORS_ORIGIN || '*',
  defaultGreenhouseCode: process.env.DEFAULT_GREENHOUSE_CODE || '0000',
  cameraCommand: process.env.CAMERA_COMMAND || 'rpicam-vid',
  cameraIndex: Number(process.env.CAMERA_INDEX || 0),
  cameraWidth: Number(process.env.CAMERA_WIDTH || 1280),
  cameraHeight: Number(process.env.CAMERA_HEIGHT || 720),
  cameraFramerate: Number(process.env.CAMERA_FRAMERATE || 15),
  cameraQuality: Number(process.env.CAMERA_QUALITY || 85),
  cameraStartTimeoutMs: Number(process.env.CAMERA_START_TIMEOUT_MS || 10_000),
  cameraIdleStopMs: Number(process.env.CAMERA_IDLE_STOP_MS || 2_000),
  hardwareMode: process.env.HARDWARE_MODE || 'mock',
  hardwareBridgePath:
    process.env.HARDWARE_BRIDGE_PATH ||
    fileURLToPath(new URL('../hardware/raspberry_bridge.py', import.meta.url)),
  hardwareTimeoutMs: Number(process.env.HARDWARE_TIMEOUT_MS || 8_000),
  gpioChip: Number(process.env.GPIO_CHIP || 0),
  dht11Pin: Number(process.env.DHT11_PIN || 24),
  bh1750I2cBus: Number(process.env.BH1750_I2C_BUS || 1),
  bh1750Address: Number(process.env.BH1750_ADDRESS || 0x23),
  soilSensorPin: Number(process.env.SOIL_SENSOR_PIN || 25),
  soilWetLevel: Number(process.env.SOIL_WET_LEVEL || 0),
  pumpPin: Number(process.env.PUMP_PIN || 18),
  lightPin: Number(process.env.LIGHT_PIN || 23),
  ventilationPin: Number(process.env.VENTILATION_PIN || 17),
  pumpActiveLow: process.env.PUMP_ACTIVE_LOW === 'true',
  lightActiveLow: process.env.LIGHT_ACTIVE_LOW === 'true',
  ventilationActiveLow: process.env.VENTILATION_ACTIVE_LOW === 'true',
  authRateLimit: Number(process.env.AUTH_RATE_LIMIT || 10),
  pairingRateLimit: Number(process.env.PAIRING_RATE_LIMIT || 10),
  rateLimitWindowMs: Number(process.env.RATE_LIMIT_WINDOW_MS || 15 * 60 * 1000),
  greenhouseOfflineAfterMs: Number(process.env.GREENHOUSE_OFFLINE_AFTER_MS || 2 * 60 * 1000)
};

if (!env.jwtSecret) {
  throw new Error('JWT_SECRET doit être défini dans le fichier .env');
}
