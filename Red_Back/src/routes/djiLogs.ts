import crypto from 'node:crypto';
import { Router } from 'express';
import { GridFSBucket } from 'mongodb';
import { connectMongo } from '../db/mongo.js';
import { requireFirebaseUser } from '../middleware/firebaseAuth.js';
import { downloadDjiFlight, flattenFlight, listDjiFlights, loginDji, requestCaptcha } from '../services/djiConsumer.js';

function cipherKey() {
  return crypto.createHash('sha256').update(process.env.DJI_SESSION_ENCRYPTION_KEY || process.env.MONGODB_URI || 'red-dji').digest();
}
function seal(value: string) {
  const iv = crypto.randomBytes(12); const cipher = crypto.createCipheriv('aes-256-gcm', cipherKey(), iv);
  const data = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return `${iv.toString('base64')}.${cipher.getAuthTag().toString('base64')}.${data.toString('base64')}`;
}
function open(value: string) {
  const [iv, tag, data] = value.split('.').map((part) => Buffer.from(part, 'base64'));
  const decipher = crypto.createDecipheriv('aes-256-gcm', cipherKey(), iv); decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
}
function upload(bucket: GridFSBucket, filename: string, buffer: Buffer, metadata: object) {
  return new Promise<unknown>((resolve, reject) => {
    const stream = bucket.openUploadStream(filename, { contentType: 'text/plain', metadata });
    stream.on('error', reject); stream.on('finish', () => resolve(stream.id)); stream.end(buffer);
  });
}

export const djiLogsRouter = Router();
djiLogsRouter.use(requireFirebaseUser);

djiLogsRouter.get('/status', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const connection = await db.collection('pilot_dji_connections').findOne({ ownerId: request.firebaseUserId! });
    response.json({ connected: Boolean(connection?.sessionToken), account: connection?.account ?? '', lastSyncAt: connection?.lastSyncAt ?? null, syncing: Boolean(connection?.syncing), error: connection?.lastError ?? '' });
  } catch (error) { next(error); }
});

djiLogsRouter.get('/captcha', async (request, response, next) => {
  try {
    const captcha = await requestCaptcha(); const db = await connectMongo();
    await db.collection('pilot_dji_connections').updateOne({ ownerId: request.firebaseUserId! }, { $set: { ownerId: request.firebaseUserId!, challengeId: captcha.challengeId, challengeAt: new Date() } }, { upsert: true });
    response.json(captcha);
  } catch (error) { next(error); }
});

djiLogsRouter.post('/connect', async (request, response, next) => {
  try {
    const account = String(request.body?.account ?? '').trim(); const password = String(request.body?.password ?? ''); const code = String(request.body?.code ?? '');
    const db = await connectMongo(); const row = await db.collection('pilot_dji_connections').findOne({ ownerId: request.firebaseUserId! });
    if (!row?.challengeId || !row?.challengeAt || Date.now() - new Date(row.challengeAt).getTime() > 300_000) return void response.status(400).json({ message: 'Solicita un CAPTCHA nuevo' });
    const token = await loginDji(account, password, String(row.challengeId), code);
    await db.collection('pilot_dji_connections').updateOne({ ownerId: request.firebaseUserId! }, { $set: { account, sessionToken: seal(token), connectedAt: new Date(), lastError: '' }, $unset: { challengeId: '', challengeAt: '' } });
    response.json({ connected: true, account });
  } catch (error) { next(error); }
});

djiLogsRouter.post('/disconnect', async (request, response, next) => {
  try { const db = await connectMongo(); await db.collection('pilot_dji_connections').updateOne({ ownerId: request.firebaseUserId! }, { $unset: { sessionToken: '' }, $set: { syncing: false } }); response.status(204).end(); } catch (error) { next(error); }
});

djiLogsRouter.post('/sync', async (request, response, next) => {
  const ownerId = request.firebaseUserId!;
  try {
    const db = await connectMongo(); const connections = db.collection('pilot_dji_connections');
    const row = await connections.findOne({ ownerId });
    if (!row?.sessionToken) return void response.status(409).json({ message: 'Conecta primero tu cuenta DJI' });
    if (row.syncing) return void response.status(202).json({ message: 'La sincronización ya está en curso' });
    await connections.updateOne({ ownerId }, { $set: { syncing: true, syncStartedAt: new Date(), lastError: '' } });
    const token = open(String(row.sessionToken)); const remote = await listDjiFlights(token); const bucket = new GridFSBucket(db, { bucketName: 'pilot_log_files' });
    const stored = await db.collection('pilot_flight_logs')
      .find({ ownerId, source: 'dji_cloud' }, { projection: { externalId: 1 } })
      .toArray();
    const existingIds = new Set(stored.map((item) => String(item.externalId)));
    let added = 0;
    for (const item of remote) {
      const flight = flattenFlight(item);
      if (existingIds.has(flight.externalId)) continue;
      const buffer = await downloadDjiFlight(token, flight.filename); const id = crypto.randomUUID(); const fileId = await upload(bucket, flight.filename, buffer, { ownerId, logId: id, source: 'dji_cloud' });
      await db.collection('pilot_flight_logs').insertOne({ id, ownerId, aircraftId: flight.aircraftSerial || 'dji', fileId, name: flight.filename, size: buffer.length, contentType: 'text/plain', source: 'dji_cloud', ...flight, addedAt: new Date() });
      existingIds.add(flight.externalId);
      added += 1;
    }
    await connections.updateOne({ ownerId }, { $set: { syncing: false, lastSyncAt: new Date(), lastError: '' }, $unset: { syncStartedAt: '' } });
    response.json({ ok: true, detected: remote.length, added });
  } catch (error) {
    const db = await connectMongo().catch(() => null); if (db) await db.collection('pilot_dji_connections').updateOne({ ownerId }, { $set: { syncing: false, lastError: (error as Error).message }, $unset: { syncStartedAt: '' } }); next(error);
  }
});

djiLogsRouter.get('/flights', async (request, response, next) => {
  try {
    const db = await connectMongo(); const rows = await db.collection('pilot_flight_logs').find({ ownerId: request.firebaseUserId!, source: 'dji_cloud' }).sort({ flownAt: -1, addedAt: -1 }).limit(500).toArray();
    response.json({ flights: rows.map(({ _id, ownerId, fileId, raw, ...row }) => row) });
  } catch (error) { next(error); }
});
