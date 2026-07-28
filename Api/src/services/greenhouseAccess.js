import { Greenhouse } from '../models/Greenhouse.js';
import { AppError } from '../utils/AppError.js';

export async function ownedGreenhouse(userId, greenhouseId) {
  const greenhouse = await Greenhouse.findOne({ _id: greenhouseId, owners: userId });
  if (!greenhouse) throw new AppError(404, 'Serre introuvable ou accès refusé');
  return greenhouse;
}
