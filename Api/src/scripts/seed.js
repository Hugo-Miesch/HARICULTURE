import { connectDatabase, disconnectDatabase } from '../config/database.js';
import { Greenhouse } from '../models/Greenhouse.js';
import { env } from '../config/env.js';

try {
  await connectDatabase();
  const greenhouse = await Greenhouse.findOneAndUpdate(
    { pairingCode: env.defaultGreenhouseCode },
    {
      $setOnInsert: {
        name: 'Serre de test',
        pairingCode: env.defaultGreenhouseCode,
        online: true,
        lastSeenAt: new Date()
      }
    },
    { new: true, upsert: true, setDefaultsOnInsert: true }
  ).select('+pairingCode');
  console.log(`Serre prête: ${greenhouse.name}, code: ${greenhouse.pairingCode}`);
} finally {
  await disconnectDatabase();
}
