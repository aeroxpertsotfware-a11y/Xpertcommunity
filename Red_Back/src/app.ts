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
  app.use((error: unknown, request: express.Request, response: express.Response, _next: express.NextFunction) => {
    if (error instanceof multer.MulterError && error.code === 'LIMIT_FILE_SIZE') {
      const limit = request.path.includes('/story')
        ? 50
        : request.path.includes('/posts')
          ? 10
        : request.path.includes('/documents/')
          ? 15
          : 5;
      response.status(413).json({ message: `El archivo no puede superar ${limit} MB` });
      return;
    }
    console.error(error);
    response.status(500).json({ message: 'Error interno del servidor' });
  });
  return app;
}
