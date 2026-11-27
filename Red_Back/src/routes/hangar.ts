import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import multer from 'multer';
import { GridFSBucket } from 'mongodb';
import { connectMongo } from '../db/mongo.js';
import { requireFirebaseUser } from '../middleware/firebaseAuth.js';

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 25 * 1024 * 1024 },
});

const allowedStatuses = new Set(['Activo', 'Mantenimiento', 'Retirado']);
const allowedLogExtensions = new Set(['txt', 'csv', 'ulg', 'bin', 'log']);

function text(value: unknown, maxLength = 160) {
  return typeof value === 'string' ? value.trim().slice(0, maxLength) : '';
}

function number(value: unknown, minimum = 0) {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? Math.max(minimum, parsed) : minimum;
}

function aircraftPayload(body: Record<string, unknown>) {
  const status = text(body.status, 30);
  return {
    name: text(body.name, 100),
    manufacturer: text(body.manufacturer, 100),
    model: text(body.model, 100),
    serialNumber: text(body.serialNumber, 120),
    status: allowedStatuses.has(status) ? status : 'Activo',
    flightHours: number(body.flightHours),
    flights: Math.floor(number(body.flights)),
    imageBase64: text(body.imageBase64, 3_000_000) || null,
  };
}

async function uploadToGridFs(bucket: GridFSBucket, file: Express.Multer.File, metadata: object) {
  return new Promise<unknown>((resolve, reject) => {
    const stream = bucket.openUploadStream(file.originalname, {
      contentType: file.mimetype,
      metadata,
    });
    stream.on('error', reject);
    stream.on('finish', () => resolve(stream.id));
    stream.end(file.buffer);
  });
}

export const hangarRouter = Router();
hangarRouter.use(requireFirebaseUser);

hangarRouter.get('/', async (request, response, next) => {
  try {
    const ownerId = request.firebaseUserId!;
    const db = await connectMongo();
    const connection = await db.collection('pilot_dji_connections').findOne({ ownerId });
    const djiAccount = String(connection?.accountKey ?? connection?.account ?? '').trim().toLowerCase();
    const logFilter = {
      ownerId,
      $or: [
        { source: { $ne: 'dji_cloud' } },
        ...(connection?.sessionToken && djiAccount
          ? [{ source: 'dji_cloud', djiAccount }]
          : []),
      ],
    };
    const [aircraft, logs] = await Promise.all([
      db.collection('pilot_aircraft').find({ ownerId }).sort({ createdAt: -1 }).toArray(),
      db.collection('pilot_flight_logs').find(logFilter).sort({ addedAt: -1 }).toArray(),
    ]);
    const logsByAircraft = new Map<string, object[]>();
    for (const log of logs) {
      const key = String(log.aircraftId);
      const list = logsByAircraft.get(key) ?? [];
      list.push({
        id: log.id,
        name: log.name,
        size: log.size,
        addedAt: log.addedAt,
        source: log.source,
        flownAt: log.flownAt,
        durationSec: log.durationSec,
        maxAltitudeM: log.maxAltitudeM,
        aircraftModel: log.aircraftModel,
      });
      logsByAircraft.set(key, list);
    }
    response.json({
      aircraft: aircraft.map(({ _id, ownerId: _ownerId, ...item }) => ({
        ...item,
        logs: logsByAircraft.get(String(item.id)) ?? [],
      })),
      logs: logs.map(({ _id, ownerId: _ownerId, fileId: _fileId, raw: _raw, ...log }) => log),
    });
  } catch (error) {
    next(error);
  }
});

hangarRouter.post('/drones', async (request, response, next) => {
  try {
    const payload = aircraftPayload(request.body ?? {});
    if (!payload.name) {
      response.status(400).json({ message: 'El nombre del dron es obligatorio' });
      return;
    }
    const now = new Date();
    const aircraft = {
      id: text(request.body?.id, 80) || randomUUID(),
      ownerId: request.firebaseUserId!,
      ...payload,
      createdAt: now,
      updatedAt: now,
    };
    const db = await connectMongo();
    await db.collection('pilot_aircraft').insertOne(aircraft);
    const { _id, ownerId, ...publicAircraft } = aircraft as typeof aircraft & { _id?: unknown };
    response.status(201).json({ aircraft: { ...publicAircraft, logs: [] } });
  } catch (error) {
    next(error);
  }
});

hangarRouter.put('/drones/:aircraftId', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const payload = aircraftPayload(request.body ?? {});
    if (!payload.name) {
      response.status(400).json({ message: 'El nombre del dron es obligatorio' });
      return;
    }
    const result = await db.collection('pilot_aircraft').findOneAndUpdate(
      { ownerId: request.firebaseUserId!, id: request.params.aircraftId },
      { $set: { ...payload, updatedAt: new Date() } },
      { returnDocument: 'after' },
    );
    if (!result) {
      response.status(404).json({ message: 'Dron no encontrado' });
      return;
    }
    const { _id, ownerId, ...aircraft } = result;
    response.json({ aircraft });
  } catch (error) {
    next(error);
  }
});

hangarRouter.delete('/drones/:aircraftId', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const filter = { ownerId: request.firebaseUserId!, aircraftId: request.params.aircraftId };
    const logs = await db.collection('pilot_flight_logs').find(filter).toArray();
    const bucket = new GridFSBucket(db, { bucketName: 'pilot_log_files' });
    await Promise.all(logs.map((log) => bucket.delete(log.fileId).catch(() => undefined)));
    await db.collection('pilot_flight_logs').deleteMany(filter);
    const result = await db.collection('pilot_aircraft').deleteOne({
      ownerId: request.firebaseUserId!,
      id: request.params.aircraftId,
    });
    if (!result.deletedCount) {
      response.status(404).json({ message: 'Dron no encontrado' });
      return;
    }
    response.status(204).end();
  } catch (error) {
    next(error);
  }
});

hangarRouter.post('/drones/:aircraftId/logs', upload.single('log'), async (request, response, next) => {
  try {
    if (!request.file) {
      response.status(400).json({ message: 'Selecciona un archivo de vuelo' });
      return;
    }
    const extension = request.file.originalname.split('.').pop()?.toLowerCase() ?? '';
    if (!allowedLogExtensions.has(extension)) {
      response.status(400).json({ message: 'Formato de bitácora no admitido' });
      return;
    }
    const db = await connectMongo();
    const ownerId = request.firebaseUserId!;
    const aircraft = await db.collection('pilot_aircraft').findOne({
      ownerId,
      id: request.params.aircraftId,
    });
    if (!aircraft) {
      response.status(404).json({ message: 'Dron no encontrado' });
      return;
    }
    const id = randomUUID();
    const addedAt = new Date();
    const bucket = new GridFSBucket(db, { bucketName: 'pilot_log_files' });
    const fileId = await uploadToGridFs(bucket, request.file, {
      ownerId,
      aircraftId: request.params.aircraftId,
      logId: id,
    });
    const log = {
      id,
      ownerId,
      aircraftId: request.params.aircraftId,
      fileId,
      name: request.file.originalname,
      size: request.file.size,
      contentType: request.file.mimetype,
      addedAt,
    };
    await db.collection('pilot_flight_logs').insertOne(log);
    response.status(201).json({
      log: { id, name: log.name, size: log.size, addedAt },
    });
  } catch (error) {
    next(error);
  }
});

hangarRouter.get('/logs/:logId/file', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const log = await db.collection('pilot_flight_logs').findOne({
      ownerId: request.firebaseUserId!,
      id: request.params.logId,
    });
    if (!log) {
      response.status(404).json({ message: 'Bitácora no encontrada' });
      return;
    }
    response.setHeader('content-type', log.contentType || 'application/octet-stream');
    response.setHeader('content-disposition', `attachment; filename*=UTF-8''${encodeURIComponent(log.name)}`);
    new GridFSBucket(db, { bucketName: 'pilot_log_files' })
      .openDownloadStream(log.fileId)
      .on('error', next)
      .pipe(response);
  } catch (error) {
    next(error);
  }
});
