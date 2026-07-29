import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { Transform } from 'node:stream';
import { env } from '../config/env.js';

export class JpegFrameParser extends Transform {
  constructor() {
    super({ readableObjectMode: true });
    this.buffer = Buffer.alloc(0);
  }

  _transform(chunk, _encoding, callback) {
    this.buffer = Buffer.concat([this.buffer, chunk]);

    while (this.buffer.length > 1) {
      const start = this.buffer.indexOf(Buffer.from([0xff, 0xd8]));
      if (start < 0) {
        this.buffer = this.buffer.subarray(Math.max(0, this.buffer.length - 1));
        break;
      }
      const end = this.buffer.indexOf(Buffer.from([0xff, 0xd9]), start + 2);
      if (end < 0) {
        if (start > 0) this.buffer = this.buffer.subarray(start);
        break;
      }

      this.push(this.buffer.subarray(start, end + 2));
      this.buffer = this.buffer.subarray(end + 2);
    }
    callback();
  }
}

export class RpicamCameraService extends EventEmitter {
  constructor({ spawnProcess = spawn } = {}) {
    super();
    this.spawnProcess = spawnProcess;
    this.process = null;
    this.starting = null;
    this.latestFrame = null;
    this.subscribers = new Set();
    this.stopTimer = null;
    this.lastError = '';
  }

  async ensureStarted() {
    if (this.process && this.latestFrame) return;
    if (this.starting) return this.starting;

    this.starting = new Promise((resolve, reject) => {
      const args = [
        '--camera',
        String(env.cameraIndex),
        '--codec',
        'mjpeg',
        '--width',
        String(env.cameraWidth),
        '--height',
        String(env.cameraHeight),
        '--framerate',
        String(env.cameraFramerate),
        '--quality',
        String(env.cameraQuality),
        '--timeout',
        '0',
        '--nopreview',
        '--output',
        '-'
      ];
      const process = this.spawnProcess(env.cameraCommand, args, {
        stdio: ['ignore', 'pipe', 'pipe']
      });
      const parser = new JpegFrameParser();
      this.process = process;
      this.latestFrame = null;
      this.lastError = '';

      const timeout = setTimeout(() => {
        fail(new Error('La caméra ne produit aucune image'));
        this.stop();
      }, env.cameraStartTimeoutMs);

      const ready = () => {
        clearTimeout(timeout);
        cleanupStartup();
        resolve();
      };
      const fail = (error) => {
        clearTimeout(timeout);
        cleanupStartup();
        reject(error);
      };
      const cleanupStartup = () => {
        this.off('ready', ready);
        this.off('startupFailure', fail);
      };

      this.once('ready', ready);
      this.once('startupFailure', fail);
      process.stdout.pipe(parser);
      parser.on('data', (frame) => {
        this.latestFrame = frame;
        if (this.starting) this.emit('ready');
        for (const subscriber of this.subscribers) subscriber(frame);
      });
      process.stderr.on('data', (chunk) => {
        this.lastError = `${this.lastError}${chunk}`.slice(-2000);
      });
      process.once('error', (error) => this.emit('startupFailure', error));
      process.once('close', (code) => {
        parser.destroy();
        const wasCurrent = this.process === process;
        if (wasCurrent) {
          this.process = null;
          this.latestFrame = null;
        }
        if (code && this.starting) {
          this.emit(
            'startupFailure',
            new Error(this.lastError.trim() || `rpicam-vid arrêté avec le code ${code}`)
          );
        }
      });
    }).finally(() => {
      this.starting = null;
    });

    return this.starting;
  }

  subscribe(subscriber) {
    clearTimeout(this.stopTimer);
    this.stopTimer = null;
    this.subscribers.add(subscriber);
    if (this.latestFrame) subscriber(this.latestFrame);

    return () => {
      this.subscribers.delete(subscriber);
      if (this.subscribers.size === 0 && this.process) {
        this.stopTimer = setTimeout(() => this.stop(), env.cameraIdleStopMs);
      }
    };
  }

  stop() {
    clearTimeout(this.stopTimer);
    this.stopTimer = null;
    if (this.process) {
      this.process.kill('SIGTERM');
      this.process = null;
    }
    this.latestFrame = null;
  }
}

export const camera = new RpicamCameraService();
