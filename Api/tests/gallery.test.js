import { describe, expect, it } from 'vitest';
import { millisecondsUntilNextMidnight } from '../src/services/galleryScheduler.js';

describe('Planification de la galerie', () => {
  it('programme la prochaine capture exactement à minuit local', () => {
    const now = new Date(2026, 6, 29, 23, 59, 30, 0);
    expect(millisecondsUntilNextMidnight(now)).toBe(30_000);
  });
});
