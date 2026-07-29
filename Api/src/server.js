import { createApp } from './app.js';
import { connectDatabase, disconnectDatabase } from './config/database.js';
import { env } from './config/env.js';
import { startRoutineScheduler, stopRoutineScheduler } from './services/routineScheduler.js';
import { camera } from './services/camera.js';
import { hardware } from './services/hardware.js';
import { startGalleryScheduler, stopGalleryScheduler } from './services/galleryScheduler.js';

let server;

async function start() {
  await connectDatabase();
  server = createApp().listen(env.port, () => {
    console.log(`API Hariculture disponible sur http://localhost:${env.port}`);
  });
  startRoutineScheduler();
  startGalleryScheduler();
}

async function shutdown() {
  stopRoutineScheduler();
  stopGalleryScheduler();
  camera.stop();
  hardware.close();
  if (server) await new Promise((resolve) => server.close(resolve));
  await disconnectDatabase();
  process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

start().catch((error) => {
  console.error('Impossible de démarrer API Hariculture:', error);
  process.exit(1);
});
