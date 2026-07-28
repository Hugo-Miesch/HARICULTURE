import mongoose from 'mongoose';
import { env } from './env.js';

export async function connectDatabase(uri = env.mongoUri) {
  mongoose.set('strictQuery', true);
  await mongoose.connect(uri);
  return mongoose.connection;
}

export async function disconnectDatabase() {
  await mongoose.disconnect();
}
