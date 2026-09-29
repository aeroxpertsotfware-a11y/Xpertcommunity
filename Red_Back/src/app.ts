import express from 'express';
import multer from 'multer';
import { profilesRouter } from './routes/profiles.js';

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '1mb' }));
  app.get('/health', (_request, response) => {
    response.json({ status: 'ok' });
  });
  app.use('/api/profiles', profilesRouter);
  app.use((error: unknown, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
    if (error instanceof multer.MulterError && error.code === 'LIMIT_FILE_SIZE') {
      response.status(413).json({ message: 'El PDF no puede superar 5 MB' });
      return;
    }
    console.error(error);
    response.status(500).json({ message: 'Error interno del servidor' });
  });
  return app;
}
