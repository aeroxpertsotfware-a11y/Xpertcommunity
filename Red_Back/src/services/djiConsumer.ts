import crypto from 'node:crypto';
import { decompressSync, unzipSync, type UnzipFileInfo } from 'fflate';

const accountBase = 'https://account-api.dji.com/apis/apprest/v1';
const flightBase = 'https://mydjiflight.dji.com/flight';
const aesKey = Buffer.from('221edf0e-edf7-42', 'utf8');
const aesIv = Buffer.from('1wdv$ESZ@QAX3rfc', 'utf8');
const macKey = '221edf0e-edf7-42b5-a451-776a5872ae4c';
const signedFields = ['AppId-Mc', 'ClientName-Mc', 'DeviceId-Mc', 'InvokeId-Mc', 'Timestamp-Mc'];
const maxFlightBytes = 512 * 1024 * 1024;

async function djiFetch(url: string, init: RequestInit = {}, timeout = 45_000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } catch (error) {
    if ((error as Error).name === 'AbortError') throw new Error('DJI no respondió a tiempo');
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

function encryptPassword(password: string) {
  const cipher = crypto.createCipheriv('aes-128-cbc', aesKey, aesIv);
  return Buffer.concat([cipher.update(password, 'utf8'), cipher.final()]).toString('hex');
}

function headers() {
  const result: Record<string, string> = {
    'InvokeId-Mc': crypto.randomUUID(),
    'DeviceId-Mc': crypto.randomUUID(),
    'Encrypted-Mc': '1',
    'AppId-Mc': 'djigo',
    'ClientName-Mc': 'android-9-4.3.61',
    'Timestamp-Mc': String(Math.floor(Date.now() / 1000)),
    'Content-Type': 'application/x-www-form-urlencoded',
  };
  const mac = crypto.createHmac('sha1', macKey);
  signedFields.forEach((field) => mac.update(field + result[field]));
  result['Sign-Mc'] = mac.digest('base64');
  return result;
}

function objects(value: unknown, output: Record<string, unknown>[] = []) {
  if (Array.isArray(value)) value.forEach((item) => objects(item, output));
  else if (value && typeof value === 'object') {
    output.push(value as Record<string, unknown>);
    Object.values(value).forEach((item) => objects(item, output));
  }
  return output;
}

function check(response: Response, payload?: Record<string, unknown>) {
  if (response.status === 401 || response.status === 403) throw new Error('La sesión DJI venció');
  if (!response.ok) throw new Error(`DJI respondió con estado ${response.status}`);
  const code = String(payload?.code ?? payload?.Code ?? '0');
  if (code !== '0' && code !== '200') {
    throw new Error(String(payload?.message ?? payload?.Message ?? payload?.msg ?? `DJI rechazó la solicitud (${code})`));
  }
}

function tokenFrom(payload: unknown) {
  for (const item of objects(payload)) {
    for (const key of ['token', 'Token', 'access_token', 'accessToken']) {
      const value = item[key];
      if (typeof value === 'string' && value.length > 15) return value;
    }
  }
  return '';
}

export async function requestCaptcha() {
  const challengeId = crypto.randomBytes(12).toString('base64url').slice(0, 6).toLowerCase();
  const response = await djiFetch(`${accountBase}/vcode?srandom=${encodeURIComponent(challengeId)}`);
  check(response);
  const mime = (response.headers.get('content-type') || 'image/png').split(';')[0];
  const image = Buffer.from(await response.arrayBuffer());
  return { challengeId, imageDataUrl: `data:${mime};base64,${image.toString('base64')}` };
}

export async function loginDji(account: string, password: string, challengeId: string, code: string) {
  const form = new URLSearchParams({
    email: account.trim().toLowerCase(),
    password: encryptPassword(password),
    srandom: challengeId,
    verificationCode: code.trim().toUpperCase(),
  });
  const response = await djiFetch(`${accountBase}/email_login`, { method: 'POST', headers: headers(), body: form });
  const payload = await response.json() as Record<string, unknown>;
  check(response, payload);
  const token = tokenFrom(payload);
  if (!token) throw new Error('DJI no devolvió una sesión válida');
  return token;
}

function listFrom(payload: unknown) {
  for (const item of objects(payload)) {
    for (const key of ['list', 'List', 'FileList', 'fileList', 'records', 'Records']) {
      if (Array.isArray(item[key])) return item[key] as Record<string, unknown>[];
    }
  }
  return null;
}

export async function validateDjiSession(token: string) {
  const url = new URL(`${flightBase}/record_info_list`);
  url.searchParams.set('token', token);
  url.searchParams.set('page', '1');
  url.searchParams.set('page_size', '1');
  const response = await djiFetch(url.toString());
  const payload = await response.json() as Record<string, unknown>;
  check(response, payload);
  if (listFrom(payload) == null) {
    throw new Error('DJI no devolvió un inventario de vuelos válido');
  }
}

export async function listDjiFlights(token: string) {
  const flights: Record<string, unknown>[] = [];
  const seen = new Set<string>();
  for (let page = 1; page <= 100; page += 1) {
    const url = new URL(`${flightBase}/record_info_list`);
    url.searchParams.set('token', token);
    url.searchParams.set('page', String(page));
    url.searchParams.set('page_size', '99');
    const response = await djiFetch(url.toString());
    const payload = await response.json() as Record<string, unknown>;
    check(response, payload);
    const batch = listFrom(payload);
    if (batch == null) throw new Error('DJI no devolvió un inventario de vuelos válido');
    for (const item of batch) {
      const key = String(item.record_id ?? item.recordId ?? item.id ?? item.file_name ?? JSON.stringify(item));
      if (!seen.has(key)) { seen.add(key); flights.push(item); }
    }
    if (batch.length < 99) break;
  }
  return flights;
}

export async function downloadDjiFlight(token: string, filename: string) {
  const url = new URL(`${flightBase}/zipdownload`);
  url.searchParams.set('token', token);
  url.searchParams.set('filename', filename);
  const response = await djiFetch(url.toString(), {}, 120_000);
  check(response);
  const buffer = Buffer.from(await response.arrayBuffer());
  if (!buffer.length || buffer.length > 512 * 1024 * 1024) throw new Error('El archivo DJI está vacío o excede 512 MB');
  return extractFlightLog(buffer);
}

function safeZipEntry(file: UnzipFileInfo) {
  const normalized = file.name.replaceAll('\\', '/');
  if (normalized.startsWith('/') || normalized.split('/').includes('..')) {
    throw new Error('DJI devolviÃ³ una ruta ZIP no segura');
  }
  if (file.originalSize > maxFlightBytes) {
    throw new Error('El log DJI descomprimido excede 512 MB');
  }
  return !normalized.endsWith('/');
}

function extractFlightLog(buffer: Buffer) {
  let output: Uint8Array = buffer;
  if (buffer.subarray(0, 4).equals(Buffer.from([0x50, 0x4b, 0x03, 0x04])) ||
      buffer.subarray(0, 4).equals(Buffer.from([0x50, 0x4b, 0x05, 0x06]))) {
    const files = unzipSync(buffer, {
      filter: (file) => safeZipEntry(file),
    });
    const entries = Object.entries(files);
    const textEntries = entries.filter(([name]) => name.toLowerCase().endsWith('.txt'));
    const selected = textEntries.length === 1
      ? textEntries[0]
      : textEntries.length === 0 && entries.length === 1
        ? entries[0]
        : null;
    if (!selected) {
      throw new Error(entries.length
        ? 'El ZIP DJI contiene varios archivos y no es posible elegir el log'
        : 'El ZIP DJI no contiene un log de vuelo');
    }
    output = selected[1];
  } else if (buffer[0] === 0x1f && buffer[1] === 0x8b) {
    output = decompressSync(buffer);
  } else if (buffer.length >= 2 && (buffer[0] & 0x0f) === 8 &&
      (buffer[0] >> 4) <= 7 && ((buffer[0] << 8) + buffer[1]) % 31 === 0) {
    output = decompressSync(buffer);
  }
  if (!output.length || output.length > maxFlightBytes) {
    throw new Error('El log DJI extraÃ­do estÃ¡ vacÃ­o o excede 512 MB');
  }
  const prefix = Buffer.from(output.subarray(0, 64)).toString('utf8').trimStart().toLowerCase();
  if (prefix.startsWith('<!doctype html') || prefix.startsWith('<html') || prefix.startsWith('{"code"')) {
    throw new Error('DJI devolviÃ³ un documento de error en lugar del log de vuelo');
  }
  return Buffer.from(output);
}

export function flattenFlight(item: Record<string, unknown>) {
  const flat: Record<string, unknown> = {};
  for (const object of objects(item)) for (const [key, value] of Object.entries(object)) if (typeof value !== 'object' && flat[key] == null) flat[key] = value;
  const pick = (...keys: string[]) => keys.map((key) => flat[key]).find((value) => value != null && value !== '');
  const number = (...keys: string[]) => { const value = Number(pick(...keys)); return Number.isFinite(value) ? value : 0; };
  const filename = String(pick('file_name', 'filename', 'FileName', 'fileName', 'name') ?? 'DJIFlightRecord.txt');
  const id = String(pick('record_id', 'recordId', 'id', 'uuid') ?? crypto.createHash('sha256').update(filename).digest('hex'));
  return {
    externalId: id,
    filename,
    durationSec: number('flightTimeSeconds', 'total_time', 'flight_time', 'duration', 'totalTime'),
    distanceM: number('total_distance', 'totalDistance', 'distance'),
    maxAltitudeM: number('max_height', 'maxHeight', 'max_altitude', 'maxAltitude'),
    maxSpeedMps: number('max_speed', 'maxSpeed'),
    aircraftSerial: String(pick('aircraft_sn', 'aircraftSn', 'drone_sn', 'droneSn', 'sn') ?? ''),
    aircraftModel: String(pick('aircraft_name', 'aircraftName', 'product_name', 'productName', 'model') ?? 'DJI aircraft'),
    flownAt: pick('start_time', 'flight_start_time', 'flightTime', 'startTime', 'create_time', 'created_at', 'time') ?? null,
    raw: item,
  };
}
