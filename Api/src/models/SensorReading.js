import mongoose from 'mongoose';

const sensorReadingSchema = new mongoose.Schema(
  {
    greenhouse: { type: mongoose.Schema.Types.ObjectId, ref: 'Greenhouse', required: true, index: true },
    temperature: { type: Number, min: -50, max: 100 },
    airHumidity: { type: Number, min: 0, max: 100 },
    soilHumidity: { type: Number, min: 0, max: 100 },
    lightLevel: { type: Number, min: 0 },
    measuredAt: { type: Date, default: Date.now, index: true }
  },
  { timestamps: true }
);

sensorReadingSchema.index({ greenhouse: 1, measuredAt: -1 });

export const SensorReading = mongoose.model('SensorReading', sensorReadingSchema);
