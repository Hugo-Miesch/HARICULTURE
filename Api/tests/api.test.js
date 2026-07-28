import { beforeAll, afterAll, afterEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';

process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = 'test-secret-at-least-32-characters-long';
process.env.MONGOMS_DISTRO = 'ubuntu-22.04';

let mongo;
let app;
let token;
let greenhouseId;

beforeAll(async () => {
  mongo = await MongoMemoryServer.create({ binary: { version: '7.0.14' } });
  const { connectDatabase } = await import('../src/config/database.js');
  const { createApp } = await import('../src/app.js');
  await connectDatabase(mongo.getUri());
  app = createApp();
});

afterEach(async () => {
  await mongoose.connection.db.collection('users').deleteMany({});
  await mongoose.connection.db.collection('greenhouses').deleteMany({});
  await mongoose.connection.db.collection('sensorreadings').deleteMany({});
  await mongoose.connection.db.collection('routines').deleteMany({});
  token = undefined;
  greenhouseId = undefined;
});

afterAll(async () => {
  await mongoose.disconnect();
  if (mongo) await mongo.stop();
});

async function registerAndPair() {
  const register = await request(app).post('/api/auth/register').send({
    name: 'Alice Test',
    email: 'alice@example.com',
    password: 'motdepasse123'
  });
  token = register.body.token;
  const pair = await request(app)
    .post('/api/greenhouses/pair')
    .set('Authorization', `Bearer ${token}`)
    .send({ code: '0000', name: 'Ma serre' });
  greenhouseId = pair.body.greenhouse._id;
  return { register, pair };
}

describe('API Hariculture', () => {
  it('signale une base connectée', async () => {
    const response = await request(app).get('/api/health');
    expect(response.status).toBe(200);
    expect(response.body.database).toBe('connected');
  });

  it('crée un compte, se connecte et protège les routes', async () => {
    const unauthorized = await request(app).get('/api/greenhouses');
    expect(unauthorized.status).toBe(401);

    const { register } = await registerAndPair();
    expect(register.status).toBe(201);
    expect(register.body.token).toBeTruthy();
    expect(register.body.user.passwordHash).toBeUndefined();

    const login = await request(app).post('/api/auth/login').send({
      email: 'alice@example.com',
      password: 'motdepasse123'
    });
    expect(login.status).toBe(200);
    expect(login.body.token).toBeTruthy();
  });

  it('associe la serre avec le code de test 0000', async () => {
    const { pair } = await registerAndPair();
    expect(pair.status).toBe(201);
    expect(pair.body.greenhouse.name).toBe('Ma serre');
    expect(pair.body.greenhouse.pairingCode).toBeUndefined();
  });

  it('commande les LED, la pompe et la fenêtre', async () => {
    await registerAndPair();
    for (const actuator of ['light', 'irrigation', 'ventilation']) {
      const response = await request(app)
        .patch(`/api/greenhouses/${greenhouseId}/actuators/${actuator}`)
        .set('Authorization', `Bearer ${token}`)
        .send({ state: true, value: 75 });
      expect(response.status).toBe(200);
      expect(response.body.actuator.state).toBe(true);
      expect(response.body.actuator.value).toBe(75);
    }
  });

  it('enregistre et retourne les données des capteurs', async () => {
    await registerAndPair();
    const created = await request(app)
      .post(`/api/greenhouses/${greenhouseId}/sensors`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        temperature: 23.4,
        airHumidity: 63,
        soilHumidity: 48,
        lightLevel: 750
      });
    expect(created.status).toBe(201);

    const latest = await request(app)
      .get(`/api/greenhouses/${greenhouseId}/sensors/latest`)
      .set('Authorization', `Bearer ${token}`);
    expect(latest.status).toBe(200);
    expect(latest.body.reading.temperature).toBe(23.4);
  });

  it('crée, modifie et supprime une routine', async () => {
    await registerAndPair();
    const created = await request(app)
      .post(`/api/greenhouses/${greenhouseId}/routines`)
      .set('Authorization', `Bearer ${token}`)
      .send({
        name: 'Arrosage du matin',
        actuator: 'irrigation',
        time: '07:30',
        days: [1, 2, 3, 4, 5],
        durationSeconds: 120,
        value: 100
      });
    expect(created.status).toBe(201);

    const routineId = created.body.routine._id;
    const updated = await request(app)
      .patch(`/api/greenhouses/${greenhouseId}/routines/${routineId}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ enabled: false });
    expect(updated.body.routine.enabled).toBe(false);

    const removed = await request(app)
      .delete(`/api/greenhouses/${greenhouseId}/routines/${routineId}`)
      .set('Authorization', `Bearer ${token}`);
    expect(removed.status).toBe(204);
  });

  it('refuse les valeurs de capteurs invalides', async () => {
    await registerAndPair();
    const response = await request(app)
      .post(`/api/greenhouses/${greenhouseId}/sensors`)
      .set('Authorization', `Bearer ${token}`)
      .send({ airHumidity: 140 });
    expect(response.status).toBe(400);
  });
});
