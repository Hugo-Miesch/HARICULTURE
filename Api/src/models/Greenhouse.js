import mongoose from 'mongoose';

const actuatorSchema = new mongoose.Schema(
  {
    state: { type: Boolean, default: false },
    value: { type: Number, min: 0, max: 100, default: 0 },
    updatedAt: { type: Date, default: Date.now }
  },
  { _id: false }
);

const greenhouseSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 80 },
    pairingCode: { type: String, required: true, unique: true, select: false },
    owners: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
    location: { type: String, trim: true, maxlength: 160 },
    online: { type: Boolean, default: false },
    lastSeenAt: Date,
    actuators: {
      light: { type: actuatorSchema, default: () => ({}) },
      irrigation: { type: actuatorSchema, default: () => ({}) },
      ventilation: { type: actuatorSchema, default: () => ({}) }
    },
    camera: {
      enabled: { type: Boolean, default: true },
      streamPath: { type: String, default: '/api/greenhouses/:id/camera/stream' }
    }
  },
  { timestamps: true }
);

export const Greenhouse = mongoose.model('Greenhouse', greenhouseSchema);
