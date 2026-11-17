import { Router } from 'express';
import { Readable } from 'node:stream';
import multer from 'multer';
import { GridFSBucket, ObjectId } from 'mongodb';
import { connectMongo } from '../db/mongo.js';
import { requireFirebaseUser } from '../middleware/firebaseAuth.js';

const router = Router();
const documentUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_request, file, callback) => {
    callback(null, ['application/pdf', 'image/jpeg', 'image/png'].includes(file.mimetype));
  },
});

type CareerRole = 'piloto_uas' | 'jefe_pilotos' | 'gerente_sms';

const roles = {
  piloto_uas: {
    id: 'piloto_uas',
    title: 'Piloto UAS',
    subtitle: 'Opera aeronaves no tripuladas en categoría específica.',
    reference: 'RAC 100 · 100.610 y 100.620',
    requirements: [
      { id: 'adult', title: 'Mayor de 18 años', detail: 'Documento oficial de identidad vigente.' },
      { id: 'pilot_course', title: 'Curso de Piloto UAS', detail: 'Mínimo 94 horas: 78 teóricas y 16 prácticas.' },
      { id: 'ova', title: 'Curso OVA completado', detail: 'Objeto Virtual de Aprendizaje del CEA.' },
      { id: 'exam', title: 'Examen de Aerocivil aprobado', detail: 'Calificación mínima del 75 %.' },
      { id: 'suitability', title: 'Certificado de idoneidad', detail: 'Certificado expedido por Aerocivil.' },
      { id: 'medical', title: 'Certificado médico vigente', detail: 'Certificado médico ocupacional aplicable a la operación.' },
    ],
  },
  jefe_pilotos: {
    id: 'jefe_pilotos',
    title: 'Jefe de Pilotos UAS',
    subtitle: 'Lidera pilotos, competencias y procedimientos operacionales.',
    reference: 'RAC 100 · 100.520(d)(1)',
    requirements: [
      { id: 'uas_training', title: 'Capacitación como Piloto UAS', detail: 'En al menos una operación autorizada al explotador.' },
      { id: 'flight_hours', title: '100 horas de vuelo', detail: 'En UAS similares a los utilizados por el explotador.' },
      { id: 'admin_experience', title: 'Experiencia administrativa', detail: '6 meses en operaciones UAS o 1 año en aviación tripulada.' },
      { id: 'sms_course', title: 'Curso SMS de 40 horas', detail: 'Certificado por un CIAC o CEAC.' },
    ],
  },
  gerente_sms: {
    id: 'gerente_sms',
    title: 'Gerente de Seguridad Operacional',
    subtitle: 'Gestiona peligros, riesgos y mejora continua del SMS.',
    reference: 'RAC 100 · 100.520(e)(1)',
    requirements: [
      { id: 'sms_course', title: 'Curso SMS de 40 horas', detail: 'Certificado por un CIAC o CEAC.' },
      { id: 'aeronautical_training', title: 'Formación aeronáutica', detail: 'Conocimientos demostrables en áreas del sector aeronáutico.' },
      { id: 'operational_experience', title: '12 meses de experiencia', detail: 'Experiencia operacional aeronáutica acreditable.' },
    ],
  },
} satisfies Record<CareerRole, {
  id: CareerRole;
  title: string;
  subtitle: string;
  reference: string;
  requirements: Array<{ id: string; title: string; detail: string }>;
}>;

function validRole(value: unknown): value is CareerRole {
  return typeof value === 'string' && value in roles;
}

function normalizedApplication(application: Record<string, any>, role: CareerRole) {
  const documents = (application.documents ?? {}) as Record<string, any>;
  const complete = roles[role].requirements.every((item) => documents[item.id]?.fileId);
  return {
    ...application,
    role,
    status: application.status === 'submitted' && complete ? 'submitted' : 'draft',
    documents,
  };
}

function storedApplications(document: Record<string, any> | null) {
  if (!document) return {} as Partial<Record<CareerRole, Record<string, any>>>;
  const applications = { ...((document.applications ?? {}) as Record<string, any>) };
  if (validRole(document.role) && !applications[document.role]) {
    applications[document.role] = {
      role: document.role,
      status: document.status,
      documents: document.documents ?? {},
      notes: document.notes,
      createdAt: document.createdAt,
      updatedAt: document.updatedAt,
      submittedAt: document.submittedAt,
    };
  }
  return Object.fromEntries(
    Object.entries(applications)
      .filter(([role]) => validRole(role))
      .map(([role, application]) => [
        role,
        normalizedApplication(application as Record<string, any>, role as CareerRole),
      ]),
  ) as Partial<Record<CareerRole, Record<string, any>>>;
}

function publicApplication(application: Record<string, any> | null) {
  if (!application) return null;
  const { documents: rawDocuments, ...safe } = application;
  const documents = Object.fromEntries(
    Object.entries((rawDocuments ?? {}) as Record<string, any>).map(([key, value]) => [
      key,
      {
        name: value?.name,
        contentType: value?.contentType,
        size: value?.size,
        uploadedAt: value?.uploadedAt,
      },
    ]),
  );
  return { ...safe, documents };
}

function publicApplications(document: Record<string, any> | null) {
  return Object.fromEntries(
    Object.entries(storedApplications(document)).map(([role, application]) => [
      role,
      publicApplication(application ?? null),
    ]),
  );
}

router.use(requireFirebaseUser);

router.get('/me', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const document = await db.collection('career_applications').findOne({
      userId: request.firebaseUserId,
    });
    response.json({ roles: Object.values(roles), applications: publicApplications(document) });
  } catch (error) {
    next(error);
  }
});

router.put('/me', async (request, response, next) => {
  try {
    if (!validRole(request.body?.role)) {
      response.status(400).json({ message: 'Selecciona un cargo válido.' });
      return;
    }
    const role: CareerRole = request.body.role;
    const now = new Date();
    const db = await connectMongo();
    const current = await db.collection('career_applications').findOne({
      userId: request.firebaseUserId,
    });
    const existing = storedApplications(current)[role];
    const application = {
      ...(existing ?? {}),
      role,
      status: existing?.status ?? 'draft',
      documents: existing?.documents ?? {},
      notes: String(request.body?.notes ?? existing?.notes ?? '').trim().slice(0, 1000),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    };
    await db.collection('career_applications').updateOne(
      { userId: request.firebaseUserId },
      {
        $set: {
          [`applications.${role}`]: application,
          updatedAt: now,
        },
        $setOnInsert: {
          userId: request.firebaseUserId,
          createdAt: now,
        },
      },
      { upsert: true },
    );
    const updated = await db.collection('career_applications').findOne({
      userId: request.firebaseUserId,
    });
    response.json({
      application: publicApplication(storedApplications(updated)[role] ?? null),
      applications: publicApplications(updated),
    });
  } catch (error) {
    next(error);
  }
});

router.post(
  '/me/:role/requirements/:requirementId/document',
  documentUpload.single('document'),
  async (request, response, next) => {
    try {
      if (!request.file) {
        response.status(400).json({ message: 'Adjunta un archivo PDF, JPG o PNG de máximo 10 MB.' });
        return;
      }
      const db = await connectMongo();
      if (!validRole(request.params.role)) {
        response.status(400).json({ message: 'Selecciona un cargo válido.' });
        return;
      }
      const role: CareerRole = request.params.role;
      const document = await db.collection('career_applications').findOne({
        userId: request.firebaseUserId,
      });
      const application = storedApplications(document)[role];
      if (!application) {
        response.status(400).json({ message: 'Selecciona primero el cargo profesional.' });
        return;
      }
      if (application.status === 'submitted') {
        response.status(409).json({ message: 'La postulación ya fue enviada.' });
        return;
      }
      const requirement = roles[role].requirements.find(
        (item) => item.id === request.params.requirementId,
      );
      if (!requirement) {
        response.status(400).json({ message: 'El requisito no pertenece al cargo seleccionado.' });
        return;
      }

      const bucket = new GridFSBucket(db, { bucketName: 'career_documents' });
      const fileId = new ObjectId();
      await new Promise<void>((resolve, reject) => {
        Readable.from(request.file!.buffer)
          .pipe(bucket.openUploadStreamWithId(fileId, request.file!.originalname, {
            contentType: request.file!.mimetype,
            metadata: {
              userId: request.firebaseUserId,
              requirementId: requirement.id,
              role,
            },
          }))
          .on('error', reject)
          .on('finish', () => resolve());
      });

      const now = new Date();
      await db.collection('career_applications').updateOne(
        { userId: request.firebaseUserId },
        {
          $set: {
            [`applications.${role}.documents.${requirement.id}`]: {
              fileId,
              name: request.file.originalname,
              contentType: request.file.mimetype,
              size: request.file.size,
              uploadedAt: now,
            },
            [`applications.${role}.status`]: 'draft',
            [`applications.${role}.updatedAt`]: now,
            updatedAt: now,
          },
        },
      );
      const updated = await db.collection('career_applications').findOne({
        userId: request.firebaseUserId,
      });
      response.json({
        application: publicApplication(storedApplications(updated)[role] ?? null),
        applications: publicApplications(updated),
      });
    } catch (error) {
      next(error);
    }
  },
);

router.post('/me/:role/submit', async (request, response, next) => {
  try {
    if (!validRole(request.params.role)) {
      response.status(400).json({ message: 'Selecciona un cargo válido.' });
      return;
    }
    const role: CareerRole = request.params.role;
    const db = await connectMongo();
    const document = await db.collection('career_applications').findOne({
      userId: request.firebaseUserId,
    });
    const application = storedApplications(document)[role];
    if (!application) {
      response.status(400).json({ message: 'Primero crea una postulación.' });
      return;
    }
    const missing = roles[role].requirements.filter(
      (item) => !application.documents?.[item.id]?.fileId,
    );
    if (missing.length > 0) {
      response.status(400).json({
        message: 'Aún tienes requisitos pendientes.',
        missing: missing.map((item) => item.id),
      });
      return;
    }
    const now = new Date();
    await db.collection('career_applications').updateOne(
      { userId: request.firebaseUserId },
      {
        $set: {
          [`applications.${role}.status`]: 'submitted',
          [`applications.${role}.submittedAt`]: now,
          [`applications.${role}.updatedAt`]: now,
          updatedAt: now,
        },
      },
    );
    const updated = await db.collection('career_applications').findOne({
      userId: request.firebaseUserId,
    });
    response.json({
      application: publicApplication(storedApplications(updated)[role] ?? null),
      applications: publicApplications(updated),
    });
  } catch (error) {
    next(error);
  }
});

export const careerRouter = router;
