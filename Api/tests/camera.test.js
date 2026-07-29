import { PassThrough } from 'node:stream';
import { EventEmitter } from 'node:events';
import { describe, expect, it, vi } from 'vitest';
import { JpegFrameParser, RpicamCameraService } from '../src/services/camera.js';

const jpeg = (...payload) => Buffer.from([0xff, 0xd8, ...payload, 0xff, 0xd9]);

describe('Service caméra Raspberry', () => {
  it('reconstitue les images JPEG même lorsque les chunks sont fragmentés', async () => {
    const parser = new JpegFrameParser();
    const frames = [];
    parser.on('data', (frame) => frames.push(frame));

    parser.write(Buffer.from([0x00, 0xff]));
    parser.write(Buffer.concat([Buffer.from([0xd8, 0x01]), Buffer.from([0x02, 0xff])]));
    parser.end(Buffer.concat([Buffer.from([0xd9]), jpeg(0x03, 0x04)]));
    await new Promise((resolve) => parser.once('end', resolve));

    expect(frames).toEqual([jpeg(0x01, 0x02), jpeg(0x03, 0x04)]);
  });

  it('lance rpicam-vid une seule fois et partage la dernière image', async () => {
    const child = new EventEmitter();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    child.kill = vi.fn();
    const spawnProcess = vi.fn(() => child);
    const service = new RpicamCameraService({ spawnProcess });

    const started = service.ensureStarted();
    child.stdout.write(jpeg(0x42));
    await started;

    const received = [];
    const unsubscribe = service.subscribe((frame) => received.push(frame));
    await service.ensureStarted();

    expect(spawnProcess).toHaveBeenCalledTimes(1);
    expect(spawnProcess.mock.calls[0][0]).toBe('rpicam-vid');
    expect(spawnProcess.mock.calls[0][1]).toContain('mjpeg');
    expect(received).toEqual([jpeg(0x42)]);

    unsubscribe();
    service.stop();
    expect(child.kill).toHaveBeenCalledWith('SIGTERM');
  });

  it('fournit une copie de la dernière image pour une capture photo', async () => {
    const child = new EventEmitter();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    child.kill = vi.fn();
    const service = new RpicamCameraService({ spawnProcess: () => child });

    const captured = service.captureFrame();
    child.stdout.write(jpeg(0x24));

    expect(await captured).toEqual(jpeg(0x24));
    service.stop();
  });
});
