import { Router } from 'express';
import { connectMongo } from '../db/mongo.js';
import { requireFirebaseUser } from '../middleware/firebaseAuth.js';

const router = Router();

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

function publicApplication(application: Record<string, any> | null) {
  if (!application) return null;
  const { _id, ...safe } = application;
  return { ...safe, id: String(_id) };
}

router.use(requireFirebaseUser);

router.get('/me', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const application = await db.collection('career_applications').findOne({
      userId: request.firebaseUserId,
    });
    response.json({ roles: Object.values(roles), application: publicApplication(application) });
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
    const allowedRequirements = new Set(roles[role].requirements.map((item) => item.id));
    const checks = Object.fromEntries(
      Object.entries(request.body?.checks ?? {})
        .filter(([key]) => allowedRequirements.has(key))
        .map(([key, value]) => [key, value === true]),
    );
    const now = new Date();
    const db = await connectMongo();
    await db.collection('career_applications').updateOne(
      { userId: request.firebaseUserId },
      {
        $set: {
          role,
          checks,
          targetCompany: String(request.body?.targetCompany ?? '').trim().slice(0, 120),
          notes: String(request.body?.notes ?? '').trim().slice(0, 1000),
          status: 'draft',
          updatedAt: now,
        },
        $setOnInsert: {
          userId: request.firebaseUserId,
          createdAt: now,
        },
      },
      { upsert: true },
    );
    const application = await db.collection('career_applications').findOne({
      userId: request.firebaseUserId,
    });
    response.json({ application: publicApplication(application) });
  } catch (error) {
    next(error);
  }
});

router.post('/me/submit', async (request, response, next) => {
  try {
    const db = await connectMongo();
    const application = await db.collection('career_applications').findOne({
      userId: request.firebaseUserId,
    });
    if (!application || !validRole(application.role)) {
      response.status(400).json({ message: 'Primero crea una postulación.' });
      return;
    }
    const missing = roles[application.role].requirements.filter(
      (item) => application.checks?.[item.id] !== true,
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
      { $set: { status: 'submitted', submittedAt: now, updatedAt: now } },
    );
    const updated = await db.collection('career_applications').findOne({
      userId: request.firebaseUserId,
    });
    response.json({ application: publicApplication(updated) });
  } catch (error) {
    next(error);
  }
});

export const careerRouter = router;
