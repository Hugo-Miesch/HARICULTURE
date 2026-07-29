import { Router } from 'express';
import mongoose from 'mongoose';
import { Photo } from '../models/Photo.js';
import { Greenhouse } from '../models/Greenhouse.js';
import { requireAuth } from '../middleware/auth.js';
import { asyncHandler } from '../utils/asyncHandler.js';
import { AppError } from '../utils/AppError.js';
import { readStoredPhoto } from '../services/galleryStorage.js';

const router = Router();
router.use(requireAuth);

function serializePhoto(photo) {
  return {
    id: photo.id,
    greenhouseId: photo.greenhouse._id.toString(),
    greenhouseName: photo.greenhouse.name,
    imageUrl: `/api/gallery/${photo.id}/file`,
    thumbnailUrl: `/api/gallery/${photo.id}/thumbnail`,
    capturedAt: photo.capturedAt.toISOString(),
    ...(photo.caption && { caption: photo.caption }),
    ...(photo.width && { width: photo.width }),
    ...(photo.height && { height: photo.height })
  };
}

router.get(
  '/',
  asyncHandler(async (req, res) => {
    const parsedLimit = Number.parseInt(req.query.limit, 10);
    const limit = Number.isFinite(parsedLimit) ? Math.min(200, Math.max(1, parsedLimit)) : 100;
    const greenhouseIds = await Greenhouse.find({ owners: req.user.id }).distinct('_id');
    const photos = await Photo.find({ greenhouse: { $in: greenhouseIds } })
      .sort({ capturedAt: -1, _id: -1 })
      .limit(limit)
      .populate('greenhouse', 'name')
      .lean({ virtuals: true });

    res.json({
      photos: photos.map((photo) =>
        serializePhoto({ ...photo, id: photo._id.toString() })
      ),
      nextCursor: null
    });
  })
);

async function authorizedPhoto(userId, photoId) {
  if (!mongoose.isValidObjectId(photoId)) throw new AppError(404, 'Photo inconnue');
  const photo = await Photo.findById(photoId).populate('greenhouse', 'name owners');
  if (!photo || !photo.greenhouse) throw new AppError(404, 'Photo inconnue');
  const isOwner = photo.greenhouse.owners.some((owner) => owner.equals(userId));
  if (!isOwner) throw new AppError(403, 'Accès interdit à cette photo');
  return photo;
}

async function sendPhoto(req, res, thumbnail) {
  const photo = await authorizedPhoto(req.user.id, req.params.photoId);
  try {
    const file = await readStoredPhoto(thumbnail ? photo.thumbnailName : photo.fileName);
    res.setHeader('Content-Type', photo.contentType);
    res.setHeader('Cache-Control', 'private, max-age=300');
    res.send(file);
  } catch (error) {
    if (process.env.NODE_ENV !== 'test') console.error('Lecture de photo impossible:', error);
    throw new AppError(500, 'Erreur de lecture du stockage');
  }
}

router.get(
  '/:photoId/file',
  asyncHandler((req, res) => sendPhoto(req, res, false))
);

router.get(
  '/:photoId/thumbnail',
  asyncHandler((req, res) => sendPhoto(req, res, true))
);

export default router;
