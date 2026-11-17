import { Router } from 'express';
import { env } from '../config/env.js';

const router = Router();
const cache = new Map<string, { expiresAt: number; payload: unknown }>();

function coordinate(value: unknown, min: number, max: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= min && parsed <= max ? parsed : null;
}

async function googleWeather(path: string, latitude: number, longitude: number) {
  const query = new URLSearchParams({
    key: env.googleWeatherApiKey,
    'location.latitude': String(latitude),
    'location.longitude': String(longitude),
    unitsSystem: 'METRIC',
    languageCode: 'es',
  });
  if (path.includes('/hours:')) query.set('hours', '6');
  const response = await fetch(`https://weather.googleapis.com/v1/${path}?${query}`, {
    signal: AbortSignal.timeout(10_000),
  });
  const payload = await response.json();
  if (!response.ok) {
    const message = (payload as any)?.error?.message || 'Weather API no respondió correctamente';
    throw new Error(message);
  }
  return payload;
}

async function spaceWeather() {
  try {
    const response = await fetch(
      'https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json',
      { signal: AbortSignal.timeout(8_000) },
    );
    if (!response.ok) return null;
    const records = (await response.json()) as Array<{
      time_tag?: string;
      Kp?: number;
      a_running?: number;
      station_count?: number;
    }>;
    const latest = records.at(-1);
    if (!latest || typeof latest.Kp !== 'number') return null;
    return {
      kp: latest.Kp,
      aIndex: latest.a_running ?? null,
      stationCount: latest.station_count ?? null,
      observedAt: latest.time_tag ?? null,
      source: 'NOAA SWPC',
    };
  } catch {
    return null;
  }
}

router.get('/', async (request, response, next) => {
  try {
    const latitude = coordinate(request.query.latitude, -90, 90);
    const longitude = coordinate(request.query.longitude, -180, 180);
    if (latitude === null || longitude === null) {
      response.status(400).json({ message: 'Coordenadas inválidas.' });
      return;
    }
    if (!env.googleWeatherApiKey) {
      response.status(503).json({ message: 'Weather API aún no está configurada.' });
      return;
    }
    const cacheKey = `${latitude.toFixed(3)},${longitude.toFixed(3)}`;
    const cached = cache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) {
      response.json(cached.payload);
      return;
    }
    const [current, hourly, geomagnetic] = await Promise.all([
      googleWeather('currentConditions:lookup', latitude, longitude),
      googleWeather('forecast/hours:lookup', latitude, longitude),
      spaceWeather(),
    ]);
    const payload = {
      current,
      hourly,
      geomagnetic,
      fetchedAt: new Date().toISOString(),
    };
    cache.set(cacheKey, { expiresAt: Date.now() + 5 * 60_000, payload });
    response.json(payload);
  } catch (error) {
    next(error);
  }
});

export const weatherRouter = router;
