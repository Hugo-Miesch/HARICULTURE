import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { env } from '../config/env.js';
import { AppError } from '../utils/AppError.js';

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

  close() {}
}

export class RaspberryPiAdapter {
  constructor({ spawnProcess = spawn } = {}) {
    this.spawnProcess = spawnProcess;
    this.process = null;
    this.starting = null;
    this.pending = new Map();
    this.nextId = 1;
    this.stderr = '';
  }

  async start() {
    if (this.process) return;
    if (this.starting) return this.starting;

    this.starting = new Promise((resolve, reject) => {
      const child = this.spawnProcess('python3', [env.hardwareBridgePath], {
        stdio: ['pipe', 'pipe', 'pipe'],
        env: {
          ...process.env,
          GPIO_CHIP: String(env.gpioChip),
          DHT11_PIN: String(env.dht11Pin),
          SOIL_SENSOR_PIN: String(env.soilSensorPin),
          SOIL_WET_LEVEL: String(env.soilWetLevel),
          BH1750_I2C_BUS: String(env.bh1750I2cBus),
          BH1750_ADDRESS: String(env.bh1750Address),
          PUMP_PIN: String(env.pumpPin),
          LIGHT_PIN: String(env.lightPin),
          VENTILATION_PIN: String(env.ventilationPin),
          PUMP_ACTIVE_LOW: String(env.pumpActiveLow),
          LIGHT_ACTIVE_LOW: String(env.lightActiveLow),
          SERVO_CLOSED_PULSE_US: String(env.servoClosedPulseUs),
          SERVO_OPEN_PULSE_US: String(env.servoOpenPulseUs),
          SERVO_FREQUENCY: String(env.servoFrequency),
          SERVO_HOLD_SECONDS: String(env.servoHoldSeconds)
        }
      });
      this.process = child;
      this.stderr = '';
      const output = createInterface({ input: child.stdout });

      output.on('line', (line) => {
        let message;
        try {
          message = JSON.parse(line);
        } catch {
          return;
        }
        if (message.event === 'ready') {
          resolve();
          return;
        }
        if (message.event === 'fatal') {
          reject(new Error(message.error));
          return;
        }
        const pending = this.pending.get(message.id);
        if (!pending) return;
        clearTimeout(pending.timeout);
        this.pending.delete(message.id);
        if (message.ok) pending.resolve(message.data);
        else pending.reject(new Error(message.error));
      });
      child.stderr.on('data', (chunk) => {
        this.stderr = `${this.stderr}${chunk}`.slice(-4000);
      });
      child.once('error', reject);
      child.once('close', (code) => {
        this.process = null;
        const error = new Error(
          this.stderr.trim() || `Pont matériel arrêté avec le code ${code}`
        );
        for (const pending of this.pending.values()) {
          clearTimeout(pending.timeout);
          pending.reject(error);
        }
        this.pending.clear();
      });
    }).finally(() => {
      this.starting = null;
    });
    return this.starting;
  }

  async request(command) {
    await this.start();
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error('Délai de réponse du matériel dépassé'));
      }, env.hardwareTimeoutMs);
      this.pending.set(id, { resolve, reject, timeout });
      this.process.stdin.write(`${JSON.stringify({ id, ...command })}\n`);
    });
  }

  async setActuator(_greenhouseId, actuator, state, value) {
    try {
      const result = await this.request({
        command: 'setActuator',
        actuator,
        state,
        value
      });
      return { ...result, value, appliedAt: new Date(result.appliedAt * 1000) };
    } catch {
      throw new AppError(503, 'Matériel Raspberry indisponible');
    }
  }

  async readSensors() {
    try {
      const result = await this.request({ command: 'readSensors' });
      if (Object.keys(result.sensorErrors || {}).length > 0) {
        console.warn('Certains capteurs sont indisponibles:', result.sensorErrors);
      }
      return Object.fromEntries(
        Object.entries(result).filter(
          ([key, value]) =>
            ['temperature', 'airHumidity', 'soilHumidity', 'lightLevel'].includes(key) &&
            Number.isFinite(value)
        )
      );
    } catch {
      throw new AppError(503, 'Capteurs Raspberry indisponibles');
    }
  }

  close() {
    if (!this.process) return;
    this.process.stdin.write(
      `${JSON.stringify({ id: this.nextId++, command: 'shutdown' })}\n`
    );
    setTimeout(() => this.process?.kill('SIGTERM'), 1000).unref();
  }
}

export const hardware =
  env.hardwareMode === 'raspberry' ? new RaspberryPiAdapter() : new MockHardwareAdapter();
