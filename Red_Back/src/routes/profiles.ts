import { Router } from 'express';
import { Readable } from 'node:stream';
import multer from 'multer';
import { GridFSBucket } from 'mongodb';
import { connectMongo } from '../db/mongo.js';

const router = Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 },
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
const storyUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 },
  fileFilter: (_request, file, callback) => {
    callback(
      null,
      ['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime']
        .includes(file.mimetype),
    );
  },
});
const postUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
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
  presence: {
    isOnline: false,
    lastSeen: null,
  },
});

router.post('/:userId/presence', async (request, response, next) => {
  try {
    const isOnline = request.body?.isOnline === true;
    const now = new Date();
    const db = await connectMongo();
    await db.collection('pilot_profiles').updateOne(
      { userId: request.params.userId },
      {
        $set: {
          presence: { isOnline, lastSeen: now },
        },
        $setOnInsert: {
          userId: request.params.userId,
          followers: 0,
          following: 0,
          createdAt: now,
        },
      },
      { upsert: true },
    );
    response.json({ isOnline, lastSeen: now });
  } catch (error) {
    next(error);
  }
});

router.get('/stories/active', async (_request, response, next) => {
  try {
    const db = await connectMongo();
    const profiles = await db
      .collection('pilot_profiles')
      .find(
        { 'story.expiresAt': { $gt: new Date() } },
        {
          projection: {
            userId: 1,
            name: 1,
            username: 1,
            story: 1,
            'images.avatar.name': 1,
            'images.avatar.uploadedAt': 1,
          },
          sort: { 'story.uploadedAt': -1 },
          limit: 30,
        },
      )
      .toArray();
    response.json(profiles);
  } catch (error) {
    next(error);
  }
});

router.get('/posts/feed', async (request, response, next) => {
  try {
    const viewerId = typeof request.query.viewerId === 'string'
      ? request.query.viewerId
      : '';
    const db = await connectMongo();
    const posts = await db
      .collection('community_posts')
      .find({})
      .sort({ createdAt: -1 })
      .limit(60)
      .toArray();
    const authorIds = [...new Set(posts.map((post) => post.userId))];
    const authors = await db
      .collection('pilot_profiles')
      .find(
        { userId: { $in: authorIds } },
        {
          projection: {
            userId: 1,
            name: 1,
            username: 1,
            'images.avatar.name': 1,
            'images.avatar.uploadedAt': 1,
          },
        },
      )
      .toArray();
    const authorMap = new Map(authors.map((author) => [author.userId, author]));
    response.json(posts.map((post) => ({
      id: post.id,
      userId: post.userId,
      content: post.content,
      createdAt: post.createdAt,
      hasImage: post.hasImage === true,
      likes: Array.isArray(post.likes) ? post.likes.length : 0,
      comments: Array.isArray(post.comments) ? post.comments.length : 0,
      reposts: Array.isArray(post.reposts) ? post.reposts.length : 0,
      liked: Array.isArray(post.likes) && post.likes.includes(viewerId),
      author: authorMap.get(post.userId) ?? null,
    })));
  } catch (error) {
    next(error);
  }
});

router.get('/posts/:postId/media', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const file = await db.collection('post_media.files').findOne({
      'metadata.postId': request.params.postId,
    });
    if (!file) {
      response.status(404).json({ message: 'Imagen no encontrada' });
      return;
    }
    response.setHeader('Content-Type', file.contentType || 'image/jpeg');
    response.setHeader('Cache-Control', 'public, max-age=3600');
    new GridFSBucket(db, { bucketName: 'post_media' })
      .openDownloadStream(file._id)
      .on('error', next)
      .pipe(response);
  } catch (error) {
    next(error);
  }
});

router.post('/posts/:postId/like', async (request, response, next) => {
  try {
    const userId = typeof request.body?.userId === 'string' ? request.body.userId : '';
    if (!userId) {
      response.status(400).json({ message: 'Falta el usuario' });
      return;
    }
    const db = await connectMongo();
    const post = await db.collection('community_posts').findOne({ id: request.params.postId });
    const liked = Array.isArray(post?.likes) && post.likes.includes(userId);
    await db.collection('community_posts').updateOne(
      { id: request.params.postId },
      liked ? { $pull: { likes: userId } } : { $addToSet: { likes: userId } },
    );
    const updated = await db.collection('community_posts').findOne({ id: request.params.postId });
    response.json({ liked: !liked, likes: Array.isArray(updated?.likes) ? updated.likes.length : 0 });
  } catch (error) {
    next(error);
  }
});

router.post('/posts/:postId/comments', async (request, response, next) => {
  try {
    const userId = typeof request.body?.userId === 'string' ? request.body.userId : '';
    const content = typeof request.body?.content === 'string'
      ? request.body.content.trim().slice(0, 500)
      : '';
    if (!userId || !content) {
      response.status(400).json({ message: 'Comentario no válido' });
      return;
    }
    const comment = { id: crypto.randomUUID(), userId, content, createdAt: new Date() };
    await (await connectMongo()).collection<any>('community_posts').updateOne(
      { id: request.params.postId },
      { $push: { comments: comment } } as any,
    );
    response.status(201).json(comment);
  } catch (error) {
    next(error);
  }
});

router.post('/posts/:postId/repost', async (request, response, next) => {
  try {
    const userId = typeof request.body?.userId === 'string' ? request.body.userId : '';
    if (!userId) {
      response.status(400).json({ message: 'Falta el usuario' });
      return;
    }
    const db = await connectMongo();
    await db.collection('community_posts').updateOne(
      { id: request.params.postId },
      { $addToSet: { reposts: userId } },
    );
    const post = await db.collection('community_posts').findOne({ id: request.params.postId });
    response.json({ reposts: Array.isArray(post?.reposts) ? post.reposts.length : 0 });
  } catch (error) {
    next(error);
  }
});

router.get('/:userId', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const profile = await db.collection('pilot_profiles').findOne(
      { userId: request.params.userId },
      { projection: safeProjection },
    );
    if (!profile) {
      response.json(defaultProfile(request.params.userId));
      return;
    }
    const posts = await db
      .collection('community_posts')
      .find({ userId: request.params.userId })
      .sort({ createdAt: -1 })
      .limit(50)
      .toArray();
    response.json({
      ...profile,
      posts: posts.map((post) => ({
        id: post.id,
        content: post.content,
        createdAt: post.createdAt,
        hasImage: post.hasImage === true,
        likes: Array.isArray(post.likes) ? post.likes.length : 0,
        comments: Array.isArray(post.comments) ? post.comments.length : 0,
        reposts: Array.isArray(post.reposts) ? post.reposts.length : 0,
        liked: Array.isArray(post.likes) && post.likes.includes(request.params.userId),
      })),
    });
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
        storage: 'gridfs',
      };
      const db = await connectMongo();
      const bucket = new GridFSBucket(db, { bucketName: 'pilot_documents' });
      const previousFiles = await db
        .collection('pilot_documents.files')
        .find({
          'metadata.userId': request.params.userId,
          'metadata.type': type,
        })
        .project({ _id: 1 })
        .toArray();
      const uploadStream = bucket.openUploadStream(document.name, {
        contentType: document.mimeType,
        metadata: { userId: request.params.userId, type },
      });
      await new Promise<void>((resolve, reject) => {
        uploadStream.once('error', reject);
        uploadStream.once('finish', () => resolve());
        Readable.from(request.file!.buffer).pipe(uploadStream);
      });
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
      await Promise.all(
        previousFiles.map(({ _id }) => bucket.delete(_id).catch(() => undefined)),
      );
      response.status(201).json(document);
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
    const storedFile = await db.collection('pilot_documents.files').findOne(
      {
        'metadata.userId': request.params.userId,
        'metadata.type': type,
      },
      { sort: { uploadDate: -1 } },
    );
    if (storedFile) {
      response.setHeader(
        'Content-Type',
        storedFile.contentType || 'application/pdf',
      );
      response.setHeader(
        'Content-Disposition',
        `inline; filename="${String(storedFile.filename).replaceAll('"', '')}"`,
      );
      const bucket = new GridFSBucket(db, { bucketName: 'pilot_documents' });
      bucket.openDownloadStream(storedFile._id).on('error', next).pipe(response);
      return;
    }
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
  '/:userId/story',
  storyUpload.single('story'),
  async (request, response, next) => {
    try {
      if (!request.file) {
        response.status(400).json({ message: 'Selecciona una foto o video válido' });
        return;
      }
      const db = await connectMongo();
      const bucket = new GridFSBucket(db, { bucketName: 'pilot_stories' });
      const previousFiles = await db
        .collection('pilot_stories.files')
        .find({ 'metadata.userId': request.params.userId })
        .project({ _id: 1 })
        .toArray();
      const uploadedAt = new Date();
      const expiresAt = new Date(uploadedAt.getTime() + 24 * 60 * 60 * 1000);
      const mediaType = request.file.mimetype.startsWith('video/')
        ? 'video'
        : 'image';
      const uploadStream = bucket.openUploadStream(
        request.file.originalname.slice(0, 160),
        {
          contentType: request.file.mimetype,
          metadata: { userId: request.params.userId, mediaType, expiresAt },
        },
      );
      await new Promise<void>((resolve, reject) => {
        uploadStream.once('error', reject);
        uploadStream.once('finish', () => resolve());
        Readable.from(request.file!.buffer).pipe(uploadStream);
      });
      const story = {
        mediaType,
        mimeType: request.file.mimetype,
        uploadedAt,
        expiresAt,
        viewCount: 0,
      };
      await db.collection('pilot_profiles').updateOne(
        { userId: request.params.userId },
        {
          $set: { story, updatedAt: uploadedAt },
          $setOnInsert: {
            userId: request.params.userId,
            followers: 0,
            following: 0,
            createdAt: uploadedAt,
          },
        },
        { upsert: true },
      );
      await Promise.all([
        ...previousFiles.map(({ _id }) =>
          bucket.delete(_id).catch(() => undefined),
        ),
        db.collection('story_views').deleteMany({ ownerId: request.params.userId }),
        db.collection('story_reactions').deleteMany({ ownerId: request.params.userId }),
      ]);
      response.status(201).json(story);
    } catch (error) {
      next(error);
    }
  },
);

router.get('/:userId/story/media', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const storedFile = await db.collection('pilot_stories.files').findOne(
      {
        'metadata.userId': request.params.userId,
        'metadata.expiresAt': { $gt: new Date() },
      },
      { sort: { uploadDate: -1 } },
    );
    if (!storedFile) {
      response.status(404).json({ message: 'Historia no encontrada' });
      return;
    }
    response.setHeader('Content-Type', storedFile.contentType);
    response.setHeader('Cache-Control', 'no-store');
    const bucket = new GridFSBucket(db, { bucketName: 'pilot_stories' });
    bucket.openDownloadStream(storedFile._id).on('error', next).pipe(response);
  } catch (error) {
    next(error);
  }
});

router.post('/:userId/story/view', async (request, response, next) => {
  try {
    const viewerId = typeof request.body?.viewerId === 'string'
      ? request.body.viewerId.trim()
      : '';
    if (!viewerId) {
      response.status(400).json({ message: 'Falta el usuario visitante' });
      return;
    }
    const db = await connectMongo();
    if (viewerId !== request.params.userId) {
      await db.collection('story_views').updateOne(
        { ownerId: request.params.userId, viewerId },
        { $setOnInsert: { ownerId: request.params.userId, viewerId, viewedAt: new Date() } },
        { upsert: true },
      );
    }
    const viewCount = await db.collection('story_views').countDocuments({
      ownerId: request.params.userId,
    });
    await db.collection('pilot_profiles').updateOne(
      { userId: request.params.userId },
      { $set: { 'story.viewCount': viewCount } },
    );
    response.json({ viewCount });
  } catch (error) {
    next(error);
  }
});

router.post('/:userId/story/reaction', async (request, response, next) => {
  try {
    const viewerId = typeof request.body?.viewerId === 'string'
      ? request.body.viewerId.trim()
      : '';
    const emoji = typeof request.body?.emoji === 'string'
      ? request.body.emoji.trim()
      : '';
    if (!viewerId || !['❤️', '👍', '😍', '😂', '😮'].includes(emoji)) {
      response.status(400).json({ message: 'Reacción no válida' });
      return;
    }
    const db = await connectMongo();
    await db.collection('story_reactions').updateOne(
      { ownerId: request.params.userId, viewerId },
      { $set: { emoji, reactedAt: new Date() } },
      { upsert: true },
    );
    response.json({ emoji });
  } catch (error) {
    next(error);
  }
});

router.delete('/:userId/story', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const bucket = new GridFSBucket(db, { bucketName: 'pilot_stories' });
    const files = await db
      .collection('pilot_stories.files')
      .find({ 'metadata.userId': request.params.userId })
      .project({ _id: 1 })
      .toArray();
    await Promise.all([
      ...files.map(({ _id }) => bucket.delete(_id).catch(() => undefined)),
      db.collection('pilot_profiles').updateOne(
        { userId: request.params.userId },
        { $unset: { story: '' } },
      ),
      db.collection('story_views').deleteMany({ ownerId: request.params.userId }),
      db.collection('story_reactions').deleteMany({ ownerId: request.params.userId }),
    ]);
    response.status(204).send();
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

router.post('/:userId/posts', postUpload.single('image'), async (request, response, next) => {
  try {
    const content =
      typeof request.body.content === 'string'
        ? request.body.content.trim().slice(0, 2000)
        : '';
    if (!content && !request.file) {
      response.status(400).json({ message: 'La publicación no puede estar vacía' });
      return;
    }
    const post = {
      id: crypto.randomUUID(),
      userId: request.params.userId,
      content,
      createdAt: new Date(),
      hasImage: Boolean(request.file),
      likes: [] as string[],
      comments: [] as Array<Record<string, unknown>>,
      reposts: [] as string[],
    };
    const db = await connectMongo();
    if (request.file) {
      const bucket = new GridFSBucket(db, { bucketName: 'post_media' });
      const stream = bucket.openUploadStream(
        request.file.originalname.slice(0, 160),
        {
          contentType: request.file.mimetype,
          metadata: { postId: post.id, userId: request.params.userId },
        },
      );
      await new Promise<void>((resolve, reject) => {
        stream.once('error', reject);
        stream.once('finish', () => resolve());
        Readable.from(request.file!.buffer).pipe(stream);
      });
    }
    await db.collection('community_posts').insertOne(post);
    await db.collection('pilot_profiles').updateOne(
      { userId: request.params.userId },
      [
        {
          $set: {
            userId: request.params.userId,
            posts: {
              $slice: [
                {
                  $concatArrays: [
                    [
                      {
                        id: post.id,
                        content: post.content,
                        createdAt: post.createdAt,
                        hasImage: post.hasImage,
                      },
                    ],
                    { $ifNull: ['$posts', []] },
                  ],
                },
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
