import { MongoClient } from 'mongodb';
import { env } from '../config/env.js';

const client = new MongoClient(env.mongodbUri);
let databasePromise: ReturnType<typeof initializeMongo> | null = null;

async function initializeMongo() {
  await client.connect();
  const db = client.db(env.mongodbDbName);
  await db.command({ ping: 1 });
  const flightLogs = db.collection('pilot_flight_logs');
  const indexes = await flightLogs.indexes();
  if (indexes.some((index) => index.name === 'unique_owner_dji_flight')) {
    await flightLogs.dropIndex('unique_owner_dji_flight');
  }
  await Promise.all([
    db.collection('pilot_profiles').createIndex(
      { userId: 1 },
      { unique: true, name: 'unique_profile_user' },
    ),
    db.collection('pilot_aircraft').createIndex(
      { ownerId: 1, id: 1 },
      { unique: true, name: 'unique_owner_aircraft' },
    ),
    db.collection('pilot_flight_logs').createIndex(
      { ownerId: 1, aircraftId: 1, addedAt: -1 },
      { name: 'owner_aircraft_logs' },
    ),
    flightLogs.createIndex(
      { ownerId: 1, source: 1, djiAccount: 1, externalId: 1 },
      {
        unique: true,
        name: 'unique_owner_dji_account_flight',
        partialFilterExpression: {
          source: 'dji_cloud',
          djiAccount: { $type: 'string' },
          externalId: { $type: 'string' },
        },
      },
    ),
    db.collection('pilot_dji_connections').createIndex(
      { ownerId: 1 },
      { unique: true, name: 'unique_owner_dji_connection' },
    ),
    db.collection('career_applications').createIndex(
      { userId: 1 },
      { unique: true, name: 'unique_career_application_user' },
    ),
    db.collection('career_applications').createIndex(
      { status: 1, role: 1, updatedAt: -1 },
      { name: 'career_application_status_role' },
    ),
  ]);
  return db;
}

export async function connectMongo() {
  databasePromise ??= initializeMongo().catch((error) => {
    databasePromise = null;
    throw error;
  });
  return databasePromise;
}

export async function closeMongo() {
  databasePromise = null;
  await client.close();
}
