import { MongoClient } from 'mongodb';
import { env } from '../config/env.js';

const client = new MongoClient(env.mongodbUri);

export async function connectMongo() {
  await client.connect();
  const db = client.db(env.mongodbDbName);
  await db.command({ ping: 1 });
  await db
    .collection('pilot_profiles')
    .createIndex({ userId: 1 }, { unique: true, name: 'unique_profile_user' });
  await db.collection('pilot_aircraft').createIndex(
    { ownerId: 1, id: 1 },
    { unique: true, name: 'unique_owner_aircraft' },
  );
  await db.collection('pilot_flight_logs').createIndex(
    { ownerId: 1, aircraftId: 1, addedAt: -1 },
    { name: 'owner_aircraft_logs' },
  );
  await db.collection('career_applications').createIndex(
    { userId: 1 },
    { unique: true, name: 'unique_career_application_user' },
  );
  await db.collection('career_applications').createIndex(
    { status: 1, role: 1, updatedAt: -1 },
    { name: 'career_application_status_role' },
  );
  return db;
}

export async function closeMongo() {
  await client.close();
}
