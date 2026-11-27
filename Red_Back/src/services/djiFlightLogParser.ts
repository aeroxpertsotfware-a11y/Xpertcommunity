import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const DJIParser = require('dji-log-parser') as new () => {
  on(event: string, callback: (record: unknown) => void): void;
  parse(buffer: Buffer): void;
};

type DjiRecord = Record<string, unknown>;

function call(record: unknown, method: string) {
  try {
    const fn = (record as DjiRecord | null)?.[method];
    return typeof fn === 'function' ? fn.call(record) : undefined;
  } catch {
    return undefined;
  }
}

function finite(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function identity(value: unknown, serial = false) {
  // DJI usa cadenas C de ancho fijo para nombre y serial. El paquete conserva
  // el relleno NUL; primero debemos cortar la cadena en el terminador.
  const text = String(value ?? '').split('\0', 1)[0].trim();
  if (!text || text.includes('\uFFFD') || /[\u0001-\u001f\u007f]/.test(text)) return undefined;
  if (serial && !/^[A-Za-z0-9._-]{4,48}$/.test(text)) return undefined;
  if (!serial && !/^[\p{L}\p{N} ._+()/-]{2,80}$/u.test(text)) return undefined;
  return text;
}

function bounded(value: unknown, minimum: number, maximum: number) {
  const parsed = finite(value);
  return parsed != null && parsed >= minimum && parsed <= maximum
    ? parsed
    : undefined;
}

// Es la misma normalización usada por la integración DJI anterior.
// Algunas versiones de FlightRecord entregan totalTime en milisegundos.
function durationSeconds(value: unknown) {
  const parsed = finite(value);
  if (parsed == null || parsed < 0) return undefined;
  return parsed >= 10800 ? parsed / 1000 : parsed;
}

export type ParsedDjiFlightLog = {
  durationSec?: number;
  distanceM?: number;
  maxAltitudeM?: number;
  maxSpeedMps?: number;
  aircraftModel?: string;
  aircraftSerial?: string;
  flownAt?: string;
  route?: Array<{ lat: number; lon: number; alt?: number }>;
};

function coordinate(value: unknown) {
  const parsed = finite(value);
  if (parsed == null) return undefined;
  return Math.abs(parsed) <= Math.PI + 0.0001
    ? parsed * 180 / Math.PI
    : parsed;
}

function downsample<T>(values: T[], maximum = 600) {
  if (values.length <= maximum) return values;
  const step = Math.ceil(values.length / maximum);
  return values.filter((_, index) => index % step === 0 || index === values.length - 1);
}

export function parseDjiFlightLog(buffer: Buffer): ParsedDjiFlightLog | null {
  const parser = new DJIParser();
  const result: ParsedDjiFlightLog = {};
  const route: Array<{ lat: number; lon: number; alt?: number }> = [];

  const readIdentity = (record: unknown) => {
    const name = identity(call(record, 'getAircraftName'));
    const type = identity(call(record, 'getDroneType'));
    const serial = identity(call(record, 'getAircraftSn'), true);
    if (name || type) result.aircraftModel = name ?? type;
    if (serial) result.aircraftSerial = serial;
  };

  parser.on('DETAILS', (record) => {
    readIdentity(record);
    const duration = durationSeconds(call(record, 'getTotalTime'));
    const distance = bounded(call(record, 'getTotalDistance'), 0, 2_000_000);
    const altitude = bounded(call(record, 'getMaxHeight'), -1000, 20_000);
    const speed = bounded(call(record, 'getMaxHSpeed'), 0, 200);
    const updateTime = call(record, 'getUpdateTime');
    if (duration != null) result.durationSec = duration;
    if (distance != null) result.distanceM = distance;
    if (altitude != null) result.maxAltitudeM = altitude;
    if (speed != null) result.maxSpeedMps = speed;
    if (updateTime) result.flownAt = String(updateTime);
  });
  parser.on('RECOVER', readIdentity);
  parser.on('OSD', (record) => {
    const lat = coordinate(call(record, 'getLatitude'));
    const lon = coordinate(call(record, 'getLongitude'));
    const alt = bounded(call(record, 'getHeight'), -1000, 20_000);
    if (lat == null || lon == null || Math.abs(lat) > 90 || Math.abs(lon) > 180 ||
        (Math.abs(lat) < 0.000001 && Math.abs(lon) < 0.000001)) return;
    const previous = route.at(-1);
    if (previous && Math.abs(previous.lat - lat) < 0.0000001 &&
        Math.abs(previous.lon - lon) < 0.0000001) return;
    route.push({ lat, lon, ...(alt != null ? { alt } : {}) });
  });

  try {
    parser.parse(buffer);
  } catch {
    return null;
  }
  if (route.length >= 2) result.route = downsample(route);
  const hasTrustedIdentity = Boolean(result.aircraftModel || result.aircraftSerial);
  const hasTrustedRoute = Boolean(result.route?.length && result.route.length >= 2);
  const hasDuration = result.durationSec != null && result.durationSec <= 24 * 3600;
  if (!hasTrustedRoute && !(hasTrustedIdentity && hasDuration)) return null;
  return result;
}
