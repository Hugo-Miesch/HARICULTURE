import mongoose from 'mongoose';

const photoSchema = new mongoose.Schema(
  {
    greenhouse: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Greenhouse',
      required: true,
      index: true
    },
    fileName: { type: String, required: true },
    thumbnailName: { type: String, required: true },
    contentType: { type: String, enum: ['image/jpeg', 'image/webp'], default: 'image/jpeg' },
    capturedAt: { type: Date, required: true, default: Date.now, index: true },
    caption: { type: String, trim: true, maxlength: 240 },
    width: { type: Number, min: 1 },
    height: { type: Number, min: 1 }
  },
  { timestamps: true }
);

photoSchema.index({ greenhouse: 1, capturedAt: -1, _id: -1 });

export const Photo = mongoose.model('Photo', photoSchema);
