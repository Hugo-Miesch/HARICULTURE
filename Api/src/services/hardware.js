import { env } from '../config/env.js';

class MockHardwareAdapter {
  async setActuator(_greenhouseId, actuator, state, value) {
    return { actuator, state, value, appliedAt: new Date() };
  }

  async readSensors() {
    return {
      temperature: 22,
      airHumidity: 60,
      soilHumidity: 48,
      lightLevel: 520
    };
  }
}

class RaspberryPiAdapter extends MockHardwareAdapter {
  async setActuator() {
    throw new Error(
      'Adaptateur GPIO non configuré. Implémentez les broches dans RaspberryPiAdapter.'
    );
  }
}

export const hardware =
  env.hardwareMode === 'raspberry' ? new RaspberryPiAdapter() : new MockHardwareAdapter();
