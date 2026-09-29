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
  return db;
}

export async function closeMongo() {
  await client.close();
}
