import { createApp } from './app.js';
import { env } from './config/env.js';
import { closeMongo, connectMongo } from './db/mongo.js';

async function main() {
  await connectMongo();
  const server = createApp().listen(env.port, () => {
    console.log(`API escuchando en el puerto ${env.port}`);
  });

  const shutdown = () => {
    server.close(() => {
      void closeMongo().finally(() => process.exit(0));
    });
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((error: unknown) => {
  console.error('No se pudo iniciar la API:', error);
  process.exit(1);
});

