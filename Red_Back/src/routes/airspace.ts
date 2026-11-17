import { Router } from 'express';

const router = Router();
const serviceUrl =
  'https://services7.arcgis.com/oJtolNh5k8HxCVtB/arcgis/rest/services/UAS_WEBLAYER/FeatureServer';
const cache = new Map<string, { expiresAt: number; payload: unknown }>();

const layers = [
  { id: 110, title: 'Zona de no vuelo dron', color: '#F04444', kind: 'znvd' },
  { id: 100, title: 'Infraestructura aeronáutica', color: '#C500FF', kind: 'infrastructure' },
  { id: 70, title: 'Helipuertos Bogotá · 3 km', color: '#F04444', kind: 'heliport' },
  { id: 60, title: 'Helipuertos · 3 km', color: '#F04444', kind: 'heliport' },
  { id: 50, title: 'Aeropuertos · 9 km', color: '#F28A45', kind: 'airport9' },
  { id: 40, title: 'Aeropuertos · 6 km', color: '#F04444', kind: 'airport6' },
  { id: 80, title: 'Áreas AIP', color: '#5479D8', kind: 'aip' },
  { id: 90, title: 'Aviación deportiva', color: '#00A884', kind: 'sport' },
  { id: 30, title: 'Helipuertos Bogotá', color: '#2B8C50', kind: 'heliportPoint' },
  { id: 20, title: 'Helipuertos', color: '#2B8C50', kind: 'heliportPoint' },
  { id: 10, title: 'Aeropuertos', color: '#1976D2', kind: 'airportPoint' },
] as const;

function coordinate(value: unknown, min: number, max: number) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= min && parsed <= max ? parsed : null;
}

async function arcgisQuery(
  layerId: number,
  geometry: string,
  geometryType: 'esriGeometryEnvelope' | 'esriGeometryPoint',
  returnGeometry: boolean,
) {
  const query = new URLSearchParams({
    where: '1=1',
    geometry,
    geometryType,
    inSR: '4326',
    spatialRel: 'esriSpatialRelIntersects',
    outFields: '*',
    returnGeometry: String(returnGeometry),
    outSR: '4326',
    f: returnGeometry ? 'geojson' : 'json',
  });
  if (returnGeometry) {
    query.set('maxAllowableOffset', '0.00004');
    query.set('resultRecordCount', '500');
  }
  const result = await fetch(`${serviceUrl}/${layerId}/query?${query}`, {
    signal: AbortSignal.timeout(12_000),
  });
  if (!result.ok) throw new Error(`ArcGIS layer ${layerId} respondió ${result.status}`);
  return result.json() as Promise<any>;
}

router.get('/', async (request, response, next) => {
  try {
    const latitude = coordinate(request.query.latitude, -90, 90);
    const longitude = coordinate(request.query.longitude, -180, 180);
    if (latitude === null || longitude === null) {
      response.status(400).json({ message: 'Coordenadas inválidas.' });
      return;
    }
    const cacheKey = `${latitude.toFixed(3)},${longitude.toFixed(3)}`;
    const cached = cache.get(cacheKey);
    if (cached && cached.expiresAt > Date.now()) {
      response.json(cached.payload);
      return;
    }

    const delta = 0.14;
    const envelope = [
      longitude - delta,
      latitude - delta,
      longitude + delta,
      latitude + delta,
    ].join(',');
    const point = `${longitude},${latitude}`;
    const polygonLayers = layers.filter((layer) => layer.id >= 40);
    const [mapResults, pointResults] = await Promise.all([
      Promise.allSettled(
        layers.map((layer) =>
          arcgisQuery(layer.id, envelope, 'esriGeometryEnvelope', true),
        ),
      ),
      Promise.allSettled(
        polygonLayers.map((layer) =>
          arcgisQuery(layer.id, point, 'esriGeometryPoint', false),
        ),
      ),
    ]);

    const features = mapResults.flatMap((result, index) => {
      if (result.status !== 'fulfilled') return [];
      const layer = layers[index];
      return (result.value.features ?? []).map((feature: any) => ({
        ...feature,
        properties: {
          ...(feature.properties ?? {}),
          _layerId: layer.id,
          _layerTitle: layer.title,
          _kind: layer.kind,
          _color: layer.color,
        },
      }));
    });
    const intersections = pointResults.flatMap((result, index) => {
      if (result.status !== 'fulfilled' || !(result.value.features?.length > 0)) return [];
      const layer = polygonLayers[index];
      return (result.value.features as any[]).map((feature) => ({
        layerId: layer.id,
        title: layer.title,
        kind: layer.kind,
        attributes: feature.attributes ?? {},
      }));
    });

    const kinds = new Set(intersections.map((item) => item.kind));
    let operation = 'allowed';
    let status = 'Operación abierta permitida';
    let maxAltitudeFeet = 400;
    if (kinds.has('znvd') || kinds.has('infrastructure') || kinds.has('heliport') ||
        kinds.has('airport6') || kinds.has('aip')) {
      operation = 'prohibited';
      status = 'Operación abierta no permitida';
      maxAltitudeFeet = 0;
    } else if (kinds.has('airport9')) {
      operation = 'conditional';
      status = 'Operación condicionada por proximidad a aeropuerto';
      maxAltitudeFeet = 200;
    } else if (kinds.has('sport')) {
      operation = 'caution';
      status = 'Precaución · actividad aeronáutica cercana';
    }

    const payload = {
      source: 'Aerocivil · Visor Geográfico UAS',
      regulation: 'RAC 100',
      operation,
      status,
      maxAltitudeFeet,
      maxAltitudeMeters: Math.round(maxAltitudeFeet * 0.3048),
      intersections,
      geojson: { type: 'FeatureCollection', features },
      notamUrl:
        'https://www.aerocivil.gov.co/publicaciones/3708/listas-de-verificacion-y-listas-de-notam-validos/',
      updatedAt: new Date().toISOString(),
    };
    cache.set(cacheKey, { expiresAt: Date.now() + 5 * 60_000, payload });
    response.json(payload);
  } catch (error) {
    next(error);
  }
});

export const airspaceRouter = router;
