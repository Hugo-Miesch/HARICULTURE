import { AppError } from '../utils/AppError.js';

const buckets = new Map();

export function createRateLimit({ windowMs, max, key = (req) => req.ip }) {
  return (req, _res, next) => {
    const now = Date.now();
    const bucketKey = key(req);
    const current = buckets.get(bucketKey);

    if (!current || current.resetAt <= now) {
      buckets.set(bucketKey, { count: 1, resetAt: now + windowMs });
      return next();
    }

    current.count += 1;
    if (current.count > max) {
      return next(new AppError(429, 'Trop de tentatives, veuillez réessayer plus tard'));
    }
    next();
  };
}

export function resetRateLimits() {
  buckets.clear();
}
