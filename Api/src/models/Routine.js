import mongoose from 'mongoose';

const routineSchema = new mongoose.Schema(
  {
    greenhouse: { type: mongoose.Schema.Types.ObjectId, ref: 'Greenhouse', required: true, index: true },
    name: { type: String, required: true, trim: true, maxlength: 80 },
    actuator: { type: String, required: true, enum: ['light', 'irrigation', 'ventilation'] },
    enabled: { type: Boolean, default: true },
    time: { type: String, required: true, match: /^([01]\d|2[0-3]):[0-5]\d$/ },
    days: [{ type: Number, min: 0, max: 6 }],
    durationSeconds: { type: Number, required: true, min: 1, max: 86400 },
    value: { type: Number, min: 0, max: 100, default: 100 },
    lastRunAt: Date
  },
  { timestamps: true }
);

export const Routine = mongoose.model('Routine', routineSchema);
