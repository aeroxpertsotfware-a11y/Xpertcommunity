import crypto from 'node:crypto';
import { Router } from 'express';
import { GridFSBucket } from 'mongodb';
import { connectMongo } from '../db/mongo.js';
import { requireFirebaseUser } from '../middleware/firebaseAuth.js';
import { downloadDjiFlight, flattenFlight, listDjiFlights, loginDji, requestCaptcha, validateDjiSession } from '../services/djiConsumer.js';
import { parseDjiFlightLog } from '../services/djiFlightLogParser.js';

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
function readStoredLog(bucket: GridFSBucket, fileId: unknown) {
  return new Promise<Buffer>((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    const stream = bucket.openDownloadStream(fileId as never);
    stream.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > 512 * 1024 * 1024) stream.destroy(new Error('El log almacenado excede 512 MB'));
      else chunks.push(chunk);
    });
    stream.on('error', reject);
    stream.on('end', () => resolve(Buffer.concat(chunks)));
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
    const accountKey = account.toLowerCase();
    const db = await connectMongo(); const row = await db.collection('pilot_dji_connections').findOne({ ownerId: request.firebaseUserId! });
    if (!row?.challengeId || !row?.challengeAt || Date.now() - new Date(row.challengeAt).getTime() > 300_000) return void response.status(400).json({ message: 'Solicita un CAPTCHA nuevo' });
    const token = await loginDji(account, password, String(row.challengeId), code);
    await validateDjiSession(token);
    await db.collection('pilot_dji_connections').updateOne({ ownerId: request.firebaseUserId! }, { $set: { account, accountKey, sessionToken: seal(token), connectedAt: new Date(), lastError: '', syncing: false }, $unset: { challengeId: '', challengeAt: '', syncStartedAt: '' } });
    response.json({ connected: true, account });
  } catch (error) { next(error); }
});

djiLogsRouter.post('/disconnect', async (request, response, next) => {
  try { const db = await connectMongo(); await db.collection('pilot_dji_connections').updateOne({ ownerId: request.firebaseUserId! }, { $unset: { sessionToken: '', account: '', accountKey: '', lastError: '', syncStartedAt: '' }, $set: { syncing: false } }); response.status(204).end(); } catch (error) { next(error); }
});

djiLogsRouter.post('/sync', async (request, response, next) => {
  const ownerId = request.firebaseUserId!;
  try {
    const db = await connectMongo(); const connections = db.collection('pilot_dji_connections');
    const row = await connections.findOne({ ownerId });
    if (!row?.sessionToken) return void response.status(409).json({ message: 'Conecta primero tu cuenta DJI' });
    const djiAccount = String(row.accountKey ?? row.account ?? '').trim().toLowerCase();
    if (!djiAccount) return void response.status(409).json({ message: 'La cuenta DJI conectada no es válida' });
    const syncStartedAt = row.syncStartedAt
      ? new Date(row.syncStartedAt).getTime()
      : 0;
    const syncIsFresh = row.syncing && Date.now() - syncStartedAt < 15 * 60_000;
    if (syncIsFresh) return void response.status(202).json({ message: 'La sincronización ya está en curso' });
    await connections.updateOne({ ownerId }, { $set: { syncing: true, syncStartedAt: new Date(), lastError: '' } });
    const token = open(String(row.sessionToken)); const remote = await listDjiFlights(token); const bucket = new GridFSBucket(db, { bucketName: 'pilot_log_files' });
    const logs = db.collection('pilot_flight_logs');
    const stored = await logs
      .find({ ownerId, source: 'dji_cloud', djiAccount }, { projection: { id: 1, externalId: 1, fileId: 1, metadataSource: 1, parserVersion: 1 } })
      .toArray();
    const storedByExternalId = new Map<string, { id: string; fileId: unknown; metadataSource?: string; parserVersion?: number }>(
      stored.map((item) => [String(item.externalId), { id: String(item.id), fileId: item.fileId, metadataSource: String(item.metadataSource ?? ''), parserVersion: Number(item.parserVersion ?? 0) }]),
    );
    let added = 0;
    let downloaded = 0;
    let failed = 0;
    const downloadErrors: string[] = [];
    for (const item of remote) {
      const flight = flattenFlight(item);
      const storedFlight = storedByExternalId.get(flight.externalId);
      if (storedFlight) {
        await logs.updateOne(
          { ownerId, id: storedFlight.id },
          { $set: { ...flight, djiAccount, name: flight.filename, aircraftId: flight.aircraftSerial || 'dji' } },
        );
      }
      if (storedFlight?.fileId) {
        if (storedFlight.metadataSource !== 'flight_log' || storedFlight.parserVersion !== 4) {
          const storedBuffer = await readStoredLog(bucket, storedFlight.fileId);
          const parsed = parseDjiFlightLog(storedBuffer);
          if (parsed) {
            await logs.updateOne(
              { ownerId, id: storedFlight.id },
              { $set: { ...parsed, metadataSource: 'flight_log', metadataValid: true, parserVersion: 4, ...(parsed.aircraftSerial ? { aircraftId: parsed.aircraftSerial } : {}) }, $unset: { decodeError: '' } },
            );
          } else {
            await logs.updateOne(
              { ownerId, id: storedFlight.id },
              {
                $set: {
                  metadataSource: 'unsupported',
                  metadataValid: false,
                  parserVersion: 4,
                  decodeError: 'El FlightRecord requiere un decodificador DJI compatible',
                  aircraftModel: flight.aircraftModel,
                  aircraftSerial: flight.aircraftSerial,
                },
                $unset: { durationSec: '', distanceM: '', maxAltitudeM: '', maxSpeedMps: '', route: '' },
              },
            );
          }
        }
        continue;
      }
      const id = String(storedFlight?.id ?? crypto.randomUUID());
      if (!storedFlight) {
        await logs.insertOne({
          id,
          ownerId,
          djiAccount,
          aircraftId: flight.aircraftSerial || 'dji',
          fileId: null,
          name: flight.filename,
          size: 0,
          contentType: 'text/plain',
          source: 'dji_cloud',
          downloadStatus: 'pending',
          ...flight,
          addedAt: new Date(),
        });
        storedByExternalId.set(flight.externalId, { id, fileId: null, metadataSource: 'dji_cloud', parserVersion: 0 });
        added += 1;
      }
      try {
        const buffer = await downloadDjiFlight(token, flight.filename);
        const parsed = parseDjiFlightLog(buffer);
        const fileId = await upload(bucket, flight.filename, buffer, { ownerId, logId: id, source: 'dji_cloud' });
        await logs.updateOne(
          { ownerId, id },
          {
            $set: {
              fileId,
              size: buffer.length,
              downloadStatus: 'completed',
              downloadedAt: new Date(),
              metadataSource: parsed ? 'flight_log' : 'unsupported',
              metadataValid: Boolean(parsed),
              parserVersion: 4,
              ...(!parsed ? { decodeError: 'El FlightRecord requiere un decodificador DJI compatible' } : {}),
              ...(parsed ?? {}),
              ...(parsed?.aircraftSerial ? { aircraftId: parsed.aircraftSerial } : {}),
            },
            $unset: { downloadError: '' },
          },
        );
        downloaded += 1;
      } catch (downloadError) {
        failed += 1;
        const downloadMessage = downloadError instanceof Error
          ? downloadError.message
          : 'No fue posible descargar el log';
        downloadErrors.push(downloadMessage);
        await logs.updateOne(
          { ownerId, id },
          { $set: { downloadStatus: 'failed', downloadError: downloadMessage } },
        );
      }
    }
    const uniqueErrors = [...new Set(downloadErrors)];
    const lastError = failed
      ? `${failed} log(s) pendientes: ${uniqueErrors.slice(0, 2).join(' · ')}`
      : '';
    await connections.updateOne({ ownerId }, { $set: { syncing: false, lastSyncAt: new Date(), lastError }, $unset: { syncStartedAt: '' } });
    response.json({ ok: true, detected: remote.length, added, downloaded, failed, message: lastError, errors: uniqueErrors });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'No fue posible sincronizar con DJI';
    const sessionExpired = /sesión DJI venció|token.*(?:inválido|vencido|expired|invalid)/i.test(message);
    const db = await connectMongo().catch(() => null); if (db) await db.collection('pilot_dji_connections').updateOne(
      { ownerId },
      {
        $set: { syncing: false, lastError: message },
        $unset: { syncStartedAt: '', ...(sessionExpired ? { sessionToken: '' } : {}) },
      },
    );
    response.status(502).json({ message });
  }
});

djiLogsRouter.get('/flights', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const connection = await db.collection('pilot_dji_connections').findOne({ ownerId: request.firebaseUserId! });
    const djiAccount = String(connection?.accountKey ?? connection?.account ?? '').trim().toLowerCase();
    if (!connection?.sessionToken || !djiAccount) return void response.json({ flights: [] });
    const rows = await db.collection('pilot_flight_logs').find({ ownerId: request.firebaseUserId!, source: 'dji_cloud', djiAccount }).sort({ flownAt: -1, addedAt: -1 }).limit(500).toArray();
    response.json({ flights: rows.map(({ _id, ownerId, fileId, raw, ...row }) => row) });
  } catch (error) { next(error); }
});
