import { Greenhouse } from '../models/Greenhouse.js';
import { captureGreenhousePhoto } from './gallery.js';

let timer;

export async function captureAllGreenhouses() {
  const greenhouses = await Greenhouse.find({
    'camera.enabled': true,
    'owners.0': { $exists: true }
  });

  for (const greenhouse of greenhouses) {
    try {
      await captureGreenhousePhoto(greenhouse);
    } catch (error) {
      console.error(`Capture automatique impossible pour la serre ${greenhouse.id}:`, error);
    }
  }
}

function millisecondsUntilNextMidnight(now = new Date()) {
  const next = new Date(now);
  next.setHours(24, 0, 0, 0);
  return next.getTime() - now.getTime();
}

function scheduleNextCapture() {
  timer = setTimeout(async () => {
    await captureAllGreenhouses();
    scheduleNextCapture();
  }, millisecondsUntilNextMidnight());
  timer.unref?.();
}

export function startGalleryScheduler() {
  if (!timer) scheduleNextCapture();
}

export function stopGalleryScheduler() {
  clearTimeout(timer);
  timer = undefined;
}

export { millisecondsUntilNextMidnight };
