import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { env } from '../config/env.js';

function storagePath(fileName) {
  return path.join(env.galleryDirectory, path.basename(fileName));
}

export async function storePhoto(frame) {
  await mkdir(env.galleryDirectory, { recursive: true });

  const id = randomUUID();
  const fileName = `${id}.jpg`;
  const thumbnailName = `${id}-thumbnail.jpg`;
  const image = sharp(frame);
  const metadata = await image.metadata();

  await Promise.all([
    writeFile(storagePath(fileName), frame, { flag: 'wx' }),
    image
      .clone()
      .rotate()
      .resize({ width: env.galleryThumbnailWidth, withoutEnlargement: true })
      .jpeg({ quality: 80 })
      .toFile(storagePath(thumbnailName))
  ]);

  return {
    fileName,
    thumbnailName,
    contentType: 'image/jpeg',
    width: metadata.width,
    height: metadata.height
  };
}

export function readStoredPhoto(fileName) {
  return readFile(storagePath(fileName));
}
