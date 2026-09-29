import 'dotenv/config';

const mongodbUri = process.env.MONGODB_URI;
const mongodbDbName = process.env.MONGODB_DB_NAME;
const port = Number(process.env.PORT ?? 4000);

if (!mongodbUri || mongodbUri.includes('TU_CLUSTER') || mongodbUri.includes('USUARIO')) {
  throw new Error('Configura MONGODB_URI en el archivo .env');
}
if (!mongodbDbName) {
  throw new Error('Configura MONGODB_DB_NAME en el archivo .env');
}
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('PORT debe ser un puerto válido');
}

export const env = { mongodbUri, mongodbDbName, port };

