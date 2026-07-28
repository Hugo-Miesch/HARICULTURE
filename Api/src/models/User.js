import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';

const userSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 80 },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    passwordHash: { type: String, required: true, select: false },
    greenhouses: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Greenhouse' }]
  },
  {
    timestamps: true,
    toJSON: {
      transform(_document, value) {
        delete value.passwordHash;
        return value;
      }
    }
  }
);

userSchema.methods.verifyPassword = function verifyPassword(password) {
  return bcrypt.compare(password, this.passwordHash);
};

userSchema.statics.hashPassword = (password) => bcrypt.hash(password, 12);

export const User = mongoose.model('User', userSchema);
