import type { NextFunction, Request, Response } from 'express';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

declare global {
  namespace Express {
    interface Request {
      firebaseUserId?: string;
    }
  }
}

function firebaseCredential() {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!raw) return undefined;
  try {
    return cert(JSON.parse(raw));
  } catch {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON no contiene un JSON válido');
  }
}

if (getApps().length === 0) {
  const credential = firebaseCredential();
  initializeApp({
    projectId: process.env.FIREBASE_PROJECT_ID || 'xpertcommunity',
    ...(credential ? { credential } : {}),
  });
}

export async function requireFirebaseUser(
  request: Request,
  response: Response,
  next: NextFunction,
) {
  const authorization = request.header('authorization') ?? '';
  const token = authorization.startsWith('Bearer ')
    ? authorization.slice(7).trim()
    : '';
  if (!token) {
    response.status(401).json({ message: 'Debes iniciar sesión' });
    return;
  }
  try {
    // La validacion de firma, audiencia y vencimiento no necesita consultar
    // el estado de revocacion en cada solicitud. Esa consulta adicional exige
    // credenciales de cuenta de servicio, que no siempre estan disponibles en
    // el entorno de despliegue.
    const decoded = await getAuth().verifyIdToken(token);
    request.firebaseUserId = decoded.uid;
    next();
  } catch {
    response.status(401).json({ message: 'La sesión no es válida o venció' });
  }
}
