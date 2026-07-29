import { Photo } from '../models/Photo.js';
import { storePhoto } from './galleryStorage.js';
import { camera } from './camera.js';

export async function captureGreenhousePhoto(
  greenhouse,
  { caption = 'Capture automatique', cameraService = camera } = {}
) {
  const frame = await cameraService.captureFrame();
  const stored = await storePhoto(frame);
  return Photo.create({
    greenhouse: greenhouse._id,
    ...stored,
    capturedAt: new Date(),
    caption
  });
}
