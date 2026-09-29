import { Router } from 'express';
import multer from 'multer';
import { connectMongo } from '../db/mongo.js';

const router = Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_request, file, callback) => {
    callback(null, file.mimetype === 'application/pdf');
  },
});
const imageUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_request, file, callback) => {
    callback(null, ['image/jpeg', 'image/png', 'image/webp'].includes(file.mimetype));
  },
});

const safeProjection = {
  'documents.resume.data': 0,
  'documents.cipu.data': 0,
  'images.avatar.data': 0,
  'images.cover.data': 0,
  'images.story.data': 0,
};

const defaultProfile = (userId: string) => ({
  userId,
  name: 'Juan Serna',
  username: 'juan.piloto',
  bio: 'Piloto UAS | Fotografía aérea y operaciones especializadas',
  location: 'Colombia',
  flightHours: 0,
  specialties: ['Fotografía aérea'],
  drones: [],
  followers: 0,
  following: 0,
  documents: {},
});

router.get('/:userId', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const profile = await db.collection('pilot_profiles').findOne(
      { userId: request.params.userId },
      { projection: safeProjection },
    );
    response.json(profile ?? defaultProfile(request.params.userId));
  } catch (error) {
    next(error);
  }
});

router.put('/:userId', async (request, response, next) => {
  try {
    const body = request.body as Record<string, unknown>;
    const text = (key: string, max: number) =>
      typeof body[key] === 'string' ? body[key].trim().slice(0, max) : '';
    const list = (key: string) =>
      Array.isArray(body[key])
        ? body[key]
            .filter((value): value is string => typeof value === 'string')
            .map((value) => value.trim())
            .filter(Boolean)
            .slice(0, 12)
        : [];
    const flightHours = Number(body.flightHours);
    const update = {
      name: text('name', 80),
      username: text('username', 40).replace(/^@/, ''),
      bio: text('bio', 220),
      location: text('location', 80),
      flightHours:
        Number.isFinite(flightHours) && flightHours >= 0 ? flightHours : 0,
      specialties: list('specialties'),
      drones: list('drones'),
      updatedAt: new Date(),
    };
    const db = await connectMongo();
    await db.collection<any>('pilot_profiles').updateOne(
      { userId: request.params.userId },
      {
        $set: update,
        $setOnInsert: {
          userId: request.params.userId,
          followers: 0,
          following: 0,
          createdAt: new Date(),
        },
      },
      { upsert: true },
    );
    const profile = await db.collection('pilot_profiles').findOne(
      { userId: request.params.userId },
      { projection: safeProjection },
    );
    response.json(profile);
  } catch (error) {
    next(error);
  }
});

router.post(
  '/:userId/documents/:type',
  upload.single('document'),
  async (request, response, next) => {
    try {
      const type = request.params.type;
      if (type !== 'resume' && type !== 'cipu') {
        response.status(400).json({ message: 'Tipo de documento no válido' });
        return;
      }
      if (!request.file) {
        response.status(400).json({ message: 'Selecciona un archivo PDF válido' });
        return;
      }
      const document = {
        name: request.file.originalname.slice(0, 160),
        mimeType: request.file.mimetype,
        size: request.file.size,
        uploadedAt: new Date(),
        data: request.file.buffer,
      };
      const db = await connectMongo();
      await db.collection('pilot_profiles').updateOne(
        { userId: request.params.userId },
        {
          $set: {
            [`documents.${type}`]: document,
            updatedAt: new Date(),
          },
          $setOnInsert: {
            userId: request.params.userId,
            followers: 0,
            following: 0,
            createdAt: new Date(),
          },
        },
        { upsert: true },
      );
      const { data: _data, ...metadata } = document;
      response.status(201).json(metadata);
    } catch (error) {
      next(error);
    }
  },
);

router.get('/:userId/documents/:type', async (request, response, next) => {
  try {
    const type = request.params.type;
    if (type !== 'resume' && type !== 'cipu') {
      response.status(400).json({ message: 'Tipo de documento no válido' });
      return;
    }
    const db = await connectMongo();
    const profile = await db
      .collection('pilot_profiles')
      .findOne({ userId: request.params.userId });
    const document = (profile?.documents as Record<string, any> | undefined)?.[
      type
    ];
    if (!document?.data) {
      response.status(404).json({ message: 'Documento no encontrado' });
      return;
    }
    response.setHeader('Content-Type', document.mimeType);
    response.setHeader(
      'Content-Disposition',
      `inline; filename="${String(document.name).replaceAll('"', '')}"`,
    );
    response.send(document.data.buffer);
  } catch (error) {
    next(error);
  }
});

router.post(
  '/:userId/images/:type',
  imageUpload.single('image'),
  async (request, response, next) => {
    try {
      const type = request.params.type;
      if (!['avatar', 'cover', 'story'].includes(type)) {
        response.status(400).json({ message: 'Tipo de imagen no válido' });
        return;
      }
      if (!request.file) {
        response.status(400).json({ message: 'Selecciona una imagen JPG, PNG o WEBP' });
        return;
      }
      const image = {
        name: request.file.originalname.slice(0, 160),
        mimeType: request.file.mimetype,
        size: request.file.size,
        uploadedAt: new Date(),
        data: request.file.buffer,
      };
      const db = await connectMongo();
      await db.collection('pilot_profiles').updateOne(
        { userId: request.params.userId },
        {
          $set: { [`images.${type}`]: image, updatedAt: new Date() },
          $setOnInsert: {
            userId: request.params.userId,
            followers: 0,
            following: 0,
            createdAt: new Date(),
          },
        },
        { upsert: true },
      );
      const { data: _data, ...metadata } = image;
      response.status(201).json(metadata);
    } catch (error) {
      next(error);
    }
  },
);

router.get('/:userId/images/:type', async (request, response, next) => {
  try {
    const type = request.params.type;
    if (!['avatar', 'cover', 'story'].includes(type)) {
      response.status(400).json({ message: 'Tipo de imagen no válido' });
      return;
    }
    const db = await connectMongo();
    const profile = await db.collection('pilot_profiles').findOne(
      { userId: request.params.userId },
      { projection: { [`images.${type}`]: 1 } },
    );
    const image = (profile?.images as Record<string, any> | undefined)?.[type];
    if (!image?.data) {
      response.status(404).json({ message: 'Imagen no encontrada' });
      return;
    }
    response.setHeader('Content-Type', image.mimeType);
    response.setHeader('Cache-Control', 'public, max-age=3600');
    response.send(image.data.buffer);
  } catch (error) {
    next(error);
  }
});

router.post('/:userId/posts', async (request, response, next) => {
  try {
    const content =
      typeof request.body.content === 'string'
        ? request.body.content.trim().slice(0, 2000)
        : '';
    if (!content) {
      response.status(400).json({ message: 'La publicación no puede estar vacía' });
      return;
    }
    const post = {
      id: crypto.randomUUID(),
      content,
      createdAt: new Date(),
      likes: 0,
      comments: 0,
    };
    const db = await connectMongo();
    await db.collection('pilot_profiles').updateOne(
      { userId: request.params.userId },
      [
        {
          $set: {
            userId: request.params.userId,
            posts: {
              $slice: [
                { $concatArrays: [[post], { $ifNull: ['$posts', []] }] },
                50,
              ],
            },
            followers: { $ifNull: ['$followers', 0] },
            following: { $ifNull: ['$following', 0] },
            createdAt: { $ifNull: ['$createdAt', new Date()] },
            updatedAt: new Date(),
          },
        },
      ],
      { upsert: true },
    );
    response.status(201).json(post);
  } catch (error) {
    next(error);
  }
});

export const profilesRouter = router;
