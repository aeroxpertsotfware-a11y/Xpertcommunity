import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_icons/phosphor_icons.dart';

import 'airspace_theme.dart';

const _conditionsApi = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://xpertcommunity-production.up.railway.app',
);

class FlightConditionsPage extends StatefulWidget {
  const FlightConditionsPage({super.key, this.airspaceOnly = false});

  final bool airspaceOnly;

  @override
  State<FlightConditionsPage> createState() => _FlightConditionsPageState();
}

class _FlightConditionsPageState extends State<FlightConditionsPage> {
  static const _gnssChannel = MethodChannel('xpertcommunity/gnss');
  Uint8List? _avatar;
  LatLng _location = const LatLng(4.7110, -74.0721);
  bool _locationReady = false;
  _WeatherSnapshot? _weather;
  _DeviceFlightData? _deviceData;
  _AirspaceSnapshot? _airspace;
  bool _loadingAirspace = true;
  String? _airspaceError;
  bool _loadingConditions = true;
  String? _conditionsError;
  Timer? _gnssTimer;
  bool _readingGnss = false;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
    _loadConditions();
  }

  @override
  void dispose() {
    _gnssTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshGnss() async {
    if (_readingGnss) return;
    _readingGnss = true;
    try {
      final raw =
          await _gnssChannel.invokeMapMethod<String, dynamic>('getStatus');
      if (!mounted || raw == null) return;
      final gnss = _GnssSnapshot.fromJson(raw);
      if (gnss.visible <= 0 || _deviceData == null) return;
      final current = _deviceData!;
      setState(() {
        _deviceData = _DeviceFlightData(
          horizontalAccuracy: current.horizontalAccuracy,
          altitude: current.altitude,
          heading: current.heading,
          speed: current.speed,
          gnss: gnss,
        );
      });
    } catch (_) {
      // El conteo de satélites no está disponible en todas las plataformas.
    } finally {
      _readingGnss = false;
    }
  }

  void _startGnssUpdates() {
    _gnssTimer?.cancel();
    _refreshGnss();
    _gnssTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _refreshGnss(),
    );
  }

  Future<void> _loadConditions() async {
    if (mounted) {
      setState(() {
        _loadingConditions = true;
        _conditionsError = null;
        _locationReady = false;
      });
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Activa la ubicación del dispositivo.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permite el acceso a la ubicación.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final deviceData = _DeviceFlightData(
        horizontalAccuracy: position.accuracy,
        altitude: position.altitude,
        heading: position.heading,
        speed: position.speed * 3.6,
        gnss: null,
      );
      final location = LatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _location = location;
          _locationReady = true;
          _deviceData = deviceData;
        });
      }
      _startGnssUpdates();
      _loadAirspace(location);
      final uri = Uri.parse('$_conditionsApi/api/weather').replace(
        queryParameters: {
          'latitude': '${position.latitude}',
          'longitude': '${position.longitude}',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map?;
        throw Exception(body?['message'] ?? 'No pudimos consultar el clima.');
      }
      final snapshot = _WeatherSnapshot.fromJson(
        (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
            .cast<String, dynamic>(),
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _location = location;
        _weather = snapshot;
        _loadingConditions = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _conditionsError = error.toString().replaceFirst('Exception: ', '');
        _loadingConditions = false;
      });
    }
  }

  Future<void> _loadAirspace(LatLng location) async {
    if (mounted) {
      setState(() {
        _loadingAirspace = true;
        _airspaceError = null;
      });
    }
    try {
      final uri = Uri.parse('$_conditionsApi/api/airspace').replace(
        queryParameters: {
          'latitude': '${location.latitude}',
          'longitude': '${location.longitude}',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw Exception('No pudimos consultar el espacio aéreo.');
      }
      final snapshot = _AirspaceSnapshot.fromJson(
        (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
            .cast<String, dynamic>(),
      );
      if (!mounted) return;
      setState(() {
        _airspace = snapshot;
        _loadingAirspace = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _airspaceError = error.toString().replaceFirst('Exception: ', '');
        _loadingAirspace = false;
      });
    }
  }

  Future<void> _loadAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final response = await http.get(
        Uri.parse('$_conditionsApi/api/profiles/${user.uid}/images/avatar'),
      );
      if (response.statusCode == 200 && mounted) {
        setState(() => _avatar = response.bodyBytes);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.airspaceOnly) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F3F2),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(top: 10),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _ConditionsHeader(
                    avatar: _avatar,
                    title: 'Espacio aéreo',
                  ),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, constraints.maxHeight - 64),
                  ),
                  child: !_locationReady
                      ? _LocationPending(
                          error: _conditionsError,
                          onRetry: _loadConditions,
                        )
                      : _AirspaceCard(
                          location: _location,
                          data: _airspace,
                          deviceData: _deviceData,
                          loading: _loadingAirspace,
                          error: _airspaceError,
                          onRetry: () => _loadAirspace(_location),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFECE4D7),
      body: Container(
        color: const Color(0xFFF3F3F2),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(top: 10),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _ConditionsHeader(avatar: _avatar),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, constraints.maxHeight - 64),
                  ),
                  child: _WeatherHero(
                    weather: _weather,
                    deviceData: _deviceData,
                    loading: _loadingConditions,
                    error: _conditionsError,
                    onRetry: _loadConditions,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConditionsHeader extends StatelessWidget {
  const _ConditionsHeader({required this.avatar, this.title = ''});
  final Uint8List? avatar;
  final String title;

  @override
  Widget build(BuildContext context) => Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Row(children: [
            const Icon(PhosphorIconsRegular.caretLeft,
                color: Colors.black, size: 17),
            if (title.isNotEmpty) ...[
              const SizedBox(width: 7),
              Text(title,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.w500)),
            ],
          ]),
        ),
        const Spacer(),
        Container(
          width: 44,
          height: 44,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: const Icon(PhosphorIconsRegular.bell,
              color: Colors.black, size: 18),
        ),
        const SizedBox(width: 9),
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.black,
          backgroundImage: avatar == null ? null : MemoryImage(avatar!),
          child: avatar == null
              ? const Icon(PhosphorIconsRegular.user, color: Colors.white)
              : null,
        ),
      ]);
}

class _ForecastPoint {
  const _ForecastPoint(this.label, this.temperature, this.rain);
  final String label;
  final double temperature;
  final bool rain;
}

class _GnssSnapshot {
  const _GnssSnapshot({required this.visible, required this.used});
  final int visible;
  final int used;

  factory _GnssSnapshot.fromJson(Map<String, dynamic> json) => _GnssSnapshot(
        visible: (json['visible'] as num?)?.round() ?? 0,
        used: (json['used'] as num?)?.round() ?? 0,
      );
}

class _DeviceFlightData {
  const _DeviceFlightData({
    required this.horizontalAccuracy,
    required this.altitude,
    required this.heading,
    required this.speed,
    required this.gnss,
  });
  final double horizontalAccuracy;
  final double altitude;
  final double heading;
  final double speed;
  final _GnssSnapshot? gnss;
}

class _WeatherSnapshot {
  const _WeatherSnapshot({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.windGust,
    required this.windDirection,
    required this.visibilityKm,
    required this.condition,
    required this.locationLabel,
    required this.forecast,
    required this.geomagnetic,
    required this.pressure,
    required this.cloudCover,
    required this.dewPoint,
    required this.uvIndex,
    required this.precipitationChance,
  });

  final double temperature;
  final double feelsLike;
  final double humidity;
  final double windSpeed;
  final double windGust;
  final double windDirection;
  final double visibilityKm;
  final String condition;
  final String locationLabel;
  final List<_ForecastPoint> forecast;
  final _GeomagneticSnapshot? geomagnetic;
  final double pressure;
  final double cloudCover;
  final double dewPoint;
  final double uvIndex;
  final double precipitationChance;

  String get flightMessage {
    if (windGust >= 35 || visibilityKm < 3) {
      return 'Condiciones no recomendadas para volar';
    }
    if (windGust >= 25 || visibilityKm < 6) {
      return 'Vuela con precaución · $condition';
    }
    return 'Buenas condiciones para volar · $condition';
  }

  factory _WeatherSnapshot.fromJson(
    Map<String, dynamic> json, {
    required double latitude,
    required double longitude,
  }) {
    final current =
        (json['current'] as Map? ?? const {}).cast<String, dynamic>();
    final hourly = (json['hourly'] as Map? ?? const {}).cast<String, dynamic>();
    final rawForecast = hourly['forecastHours'] as List? ?? const [];
    final firstHour = rawForecast.isEmpty
        ? const <String, dynamic>{}
        : (rawForecast.first as Map).cast<String, dynamic>();
    final forecast = rawForecast.map((raw) {
      final item = (raw as Map).cast<String, dynamic>();
      final time = DateTime.tryParse('${item['interval']?['startTime'] ?? ''}')
          ?.toLocal();
      final type = '${item['weatherCondition']?['type'] ?? ''}'.toLowerCase();
      return _ForecastPoint(
        time == null ? '--' : '${time.hour.toString().padLeft(2, '0')}:00',
        _weatherNumber(item['temperature']),
        type.contains('rain') ||
            type.contains('storm') ||
            type.contains('shower'),
      );
    }).toList();
    final description =
        '${current['weatherCondition']?['description']?['text'] ?? 'Clima actual'}';
    return _WeatherSnapshot(
      temperature: _weatherNumber(current['temperature']),
      feelsLike: _weatherNumber(current['feelsLikeTemperature']),
      humidity: (current['relativeHumidity'] as num?)?.toDouble() ?? 0,
      windSpeed: _weatherNumber(current['wind']?['speed']),
      windGust: _weatherNumber(current['wind']?['gust']),
      windDirection: _weatherNumber(current['wind']?['direction']),
      visibilityKm: _weatherNumber(current['visibility']),
      condition: description,
      locationLabel: '${json['locationLabel'] ?? ''}'.trim().isNotEmpty
          ? '${json['locationLabel']}'.trim()
          : '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}',
      forecast: forecast,
      geomagnetic: _GeomagneticSnapshot.fromJson(json['geomagnetic']),
      pressure: _weatherNumber(current['airPressure']?['meanSeaLevelMillibars']),
      cloudCover: _weatherNumber(current['cloudCover']),
      dewPoint: _weatherNumber(current['dewPoint']),
      uvIndex: _weatherNumber(current['uvIndex']),
      precipitationChance:
          _weatherNumber(firstHour['precipitation']?['probability']),
    );
  }
}

class _GeomagneticSnapshot {
  const _GeomagneticSnapshot({
    required this.kp,
    required this.aIndex,
    required this.stationCount,
    required this.observedAt,
  });

  final double kp;
  final int? aIndex;
  final int? stationCount;
  final DateTime? observedAt;

  String get level {
    if (kp >= 7) return 'Severo';
    if (kp >= 5) return 'Tormenta';
    if (kp >= 4) return 'Elevado';
    if (kp >= 3) return 'Moderado';
    return 'Bajo';
  }

  String get operationAdvice {
    if (kp >= 5) return 'Evita operaciones dependientes de GNSS';
    if (kp >= 4) return 'Verifica GNSS y brújula antes del vuelo';
    return 'Interferencia geomagnética baja';
  }

  static _GeomagneticSnapshot? fromJson(dynamic raw) {
    if (raw is! Map || raw['kp'] is! num) return null;
    return _GeomagneticSnapshot(
      kp: (raw['kp'] as num).toDouble(),
      aIndex: (raw['aIndex'] as num?)?.round(),
      stationCount: (raw['stationCount'] as num?)?.round(),
      observedAt: DateTime.tryParse('${raw['observedAt'] ?? ''}')?.toLocal(),
    );
  }
}

double _weatherNumber(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is Map) {
    for (final key in const [
      'degrees',
      'value',
      'distance',
      'percent',
      'millibars'
    ]) {
      final number = value[key];
      if (number is num) return number.toDouble();
    }
  }
  return 0;
}

class _WeatherHero extends StatelessWidget {
  const _WeatherHero({
    required this.weather,
    required this.deviceData,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final _WeatherSnapshot? weather;
  final _DeviceFlightData? deviceData;

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 25, 14, 18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF9CB7C0),
              Color(0xFFD0D7D1),
              Color(0xFFECE4D7),
            ],
            stops: [0, .42, 1],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
        ),
        child: Column(children: [
          const Text('Clima',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(PhosphorIconsFill.navigationArrow,
                color: Colors.white, size: 13),
            const SizedBox(width: 5),
            Text(weather?.locationLabel ?? 'Ubicación actual',
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ]),
          Text(weather == null ? '--°' : '${weather!.temperature.round()}°',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 48,
                  height: 1.05,
                  fontWeight: FontWeight.w600)),
          Text(
              loading
                  ? 'Consultando condiciones…'
                  : error ?? weather?.flightMessage ?? 'Clima no disponible',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
          if (error != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Reintentar',
                  style: TextStyle(color: Colors.white)),
            ),
          if (loading && weather == null) ...[
            const SizedBox(height: 120),
            const CircularProgressIndicator(color: AirspaceTheme.lime),
            const SizedBox(height: 12),
            const Text('Cargando datos meteorológicos…',
                style: TextStyle(color: Colors.white70, fontSize: 10)),
            const SizedBox(height: 220),
          ] else ...[
            const SizedBox(height: 16),
            _ForecastStrip(weather: weather),
            const SizedBox(height: 12),
            _TemperatureCard(weather: weather),
            const SizedBox(height: 12),
            _ConditionsWindCard(weather: weather),
            const SizedBox(height: 12),
            _GnssCard(data: deviceData),
            const SizedBox(height: 12),
            _OperationalWeatherCard(weather: weather),
            const SizedBox(height: 12),
            _KpIndexCard(data: weather?.geomagnetic),
          ],
        ]),
      );
}

class _ForecastStrip extends StatelessWidget {
  const _ForecastStrip({required this.weather});

  final _WeatherSnapshot? weather;

  @override
  Widget build(BuildContext context) {
    final items = weather?.forecast ?? const <_ForecastPoint>[];
    final visible = items.isEmpty
        ? List.generate(6, (_) => const _ForecastPoint('--', 0, false))
        : items.take(6).toList();
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: visible
            .map((item) => Expanded(
                  child: Column(children: [
                    Text(item.label == '--' ? '--' : 'Hoy',
                        style: const TextStyle(
                            color: Color(0xFF777A75), fontSize: 7)),
                    const SizedBox(height: 5),
                    Icon(
                        item.rain
                            ? PhosphorIconsFill.cloudRain
                            : PhosphorIconsFill.cloudSun,
                        color: item.rain
                            ? const Color(0xFF8CB6C2)
                            : const Color(0xFFF6C645),
                        size: 20),
                    const SizedBox(height: 4),
                    Text(
                        item.label == '--'
                            ? '--'
                            : '${item.temperature.round()}°',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(item.label,
                        style: const TextStyle(
                            color: Color(0xFF9A9C98), fontSize: 6)),
                    Text(item.rain ? 'Lluvia' : 'Parcial',
                        style: const TextStyle(
                            color: Color(0xFF777A75), fontSize: 6)),
                  ]),
                ))
            .toList(),
      ),
    );
  }
}

class _TemperatureCard extends StatelessWidget {
  const _TemperatureCard({required this.weather});

  final _WeatherSnapshot? weather;

  List<String> get _chartTimes {
    final forecast = weather?.forecast ?? const <_ForecastPoint>[];
    if (forecast.length >= 8) {
      return forecast.take(8).map((point) => point.label).toList();
    }
    final now = DateTime.now();
    return List.generate(8, (index) {
      final hour = now.add(Duration(hours: index)).hour;
      return '${hour.toString().padLeft(2, '0')}:00';
    });
  }

  @override
  Widget build(BuildContext context) => Container(
        height: 190,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(
              weather != null &&
                      weather!.condition.toLowerCase().contains('lluv')
                  ? PhosphorIconsFill.cloudRain
                  : PhosphorIconsFill.cloudSun,
              color: const Color(0xFFF4C542),
              size: 22,
            ),
            const SizedBox(width: 5),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(weather == null ? '--°' : '${weather!.temperature.round()}°',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600, height: 1)),
              const Text('Buen momento para volar',
                  style: TextStyle(color: Color(0xFF939690), fontSize: 6)),
            ]),
            const Spacer(),
            const _WeatherTab(label: 'Temperatura', selected: true),
            const _WeatherTab(label: 'Precipitación'),
            const _WeatherTab(label: 'Visibilidad'),
          ]),
          const SizedBox(height: 7),
          Expanded(
            child: Stack(children: [
              const Positioned.fill(
                bottom: 17,
                child: CustomPaint(painter: _TemperaturePainter()),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _chartTimes
                      .map((time) => Text(time,
                          style: const TextStyle(
                              color: Color(0xFFAAACA8), fontSize: 5.5)))
                      .toList(),
                ),
              ),
              Positioned(
                left: 0,
                bottom: 22,
                child: Text(
                  weather == null
                      ? 'Sensación --°'
                      : 'Sensación ${weather!.feelsLike.round()}°  ·  Humedad ${weather!.humidity.round()}%',
                  style: const TextStyle(
                      color: Color(0xFF858883), fontSize: 6),
                ),
              ),
            ]),
          ),
        ]),
      );
}

class _WeatherTab extends StatelessWidget {
  const _WeatherTab({required this.label, this.selected = false});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? AirspaceTheme.lime : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: selected ? Colors.black : const Color(0xFF9A9C98),
                  fontSize: 7)),
        );
}

class _TemperaturePainter extends CustomPainter {
  const _TemperaturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE7E9E4)
      ..strokeWidth = .7;
    for (var index = 0; index < 4; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final fillPath = Path()
      ..moveTo(0, size.height * .35)
      ..cubicTo(size.width * .18, size.height * .2, size.width * .32,
          size.height * .62, size.width * .48, size.height * .5)
      ..cubicTo(size.width * .66, size.height * .37, size.width * .8,
          size.height * .78, size.width, size.height * .62)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xE8C8FF63), Color(0x48C8FF63)],
        ).createShader(Offset.zero & size),
    );
    final linePath = Path()
      ..moveTo(0, size.height * .35)
      ..cubicTo(size.width * .18, size.height * .2, size.width * .32,
          size.height * .62, size.width * .48, size.height * .5)
      ..cubicTo(size.width * .66, size.height * .37, size.width * .8,
          size.height * .78, size.width, size.height * .62);
    canvas.drawPath(
        linePath,
        Paint()
          ..color = AirspaceTheme.lime
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    final focus = Offset(size.width * .48, size.height * .5);
    canvas.drawLine(
      Offset(focus.dx, focus.dy + 4),
      Offset(focus.dx, size.height),
      Paint()
        ..color = const Color(0xFFCED1CB)
        ..strokeWidth = .8,
    );
    canvas.drawCircle(focus, 4, Paint()..color = const Color(0xFF111311));
    canvas.drawCircle(focus, 2, Paint()..color = AirspaceTheme.lime);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ConditionsWindCard extends StatelessWidget {
  const _ConditionsWindCard({required this.weather});

  final _WeatherSnapshot? weather;

  @override
  Widget build(BuildContext context) => Container(
        height: 178,
        padding: const EdgeInsets.fromLTRB(15, 13, 13, 12),
        decoration: BoxDecoration(
          gradient: AirspaceTheme.darkGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 14,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Viento',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            const Spacer(),
            _LowBadge(),
          ]),
          const SizedBox(height: 5),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _WindScale(speed: weather?.windSpeed ?? 0),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 9),
                    const Text('Altitud máxima segura',
                        style: TextStyle(color: Colors.white38, fontSize: 7)),
                    const Text('120 m',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Row(children: [
                      _WindMetric(
                          label: 'Ráfagas',
                          value: '${weather?.windGust.round() ?? 0} km/h'),
                      const SizedBox(width: 16),
                      _WindMetric(
                          label: 'Visibilidad',
                          value:
                              '${weather?.visibilityKm.toStringAsFixed(1) ?? '--'} km'),
                    ]),
                  ],
                ),
              ),
              SizedBox(
                width: 105,
                child: Center(
                    child: _CompassDial(
                      speed: weather?.windSpeed ?? 0,
                      direction: weather?.windDirection ?? 270,
                    )),
              ),
            ]),
          ),
        ]),
      );
}

class _WindScale extends StatelessWidget {
  const _WindScale({required this.speed});
  final double speed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 42,
        child: Column(children: [
          const Text('km/h',
              style: TextStyle(color: Colors.white38, fontSize: 6)),
          const SizedBox(height: 4),
          Expanded(
            child: CustomPaint(
              size: const Size(22, double.infinity),
              painter: _WindScalePainter(speed),
            ),
          ),
          const SizedBox(height: 3),
          Text('${speed.round()}',
              style: const TextStyle(color: Colors.white, fontSize: 9)),
        ]),
      );
}

class _WindScalePainter extends CustomPainter {
  const _WindScalePainter(this.speed);
  final double speed;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = .8;
    for (var index = 0; index < 13; index++) {
      final y = size.height * index / 12;
      final longTick = index % 3 == 0;
      canvas.drawLine(Offset(longTick ? 4 : 9, y), Offset(20, y), linePaint);
    }
    final markerY = size.height * (1 - (speed.clamp(0, 50) / 50));
    canvas.drawLine(
      Offset(0, markerY),
      Offset(22, markerY),
      Paint()
        ..color = AirspaceTheme.lime
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _WindScalePainter oldDelegate) =>
      oldDelegate.speed != speed;
}

class _WindMetric extends StatelessWidget {
  const _WindMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 6)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 9)),
        ],
      );
}

class _GnssCard extends StatelessWidget {
  const _GnssCard({required this.data});
  final _DeviceFlightData? data;

  @override
  Widget build(BuildContext context) {
    final gnss = data?.gnss;
    final accuracy = data?.horizontalAccuracy;
    final quality = accuracy == null
        ? 'Sin señal'
        : accuracy <= 5
            ? 'Excelente'
            : accuracy <= 10
                ? 'Buena'
                : 'Limitada';
    return Container(
      height: 156,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: AirspaceTheme.darkGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(PhosphorIconsRegular.crosshair,
              color: AirspaceTheme.lime, size: 18),
          const SizedBox(width: 7),
          const Text('Estado GNSS',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          const Spacer(),
          if (gnss == null)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AirspaceTheme.lime,
              ),
            )
          else
            _GnssBadge(label: quality),
        ]),
        const Spacer(),
        Row(children: [
          _FlightDatum(
              label: 'Satélites visibles',
              value: gnss == null ? '--' : '${gnss.visible}',
              dark: true),
          _FlightDatum(
              label: 'Usados en posición',
              value: gnss == null ? '--' : '${gnss.used}',
              dark: true),
          _FlightDatum(
              label: 'Precisión horizontal',
              value: accuracy == null ? '--' : '${accuracy.toStringAsFixed(1)} m',
              dark: true),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _FlightDatum(
              label: 'Altitud GNSS',
              value: data == null ? '--' : '${data!.altitude.round()} m',
              dark: true),
          _FlightDatum(
              label: 'Rumbo',
              value: data == null ? '--' : '${data!.heading.round()}°',
              dark: true),
          _FlightDatum(
              label: 'Velocidad',
              value: data == null ? '--' : '${data!.speed.toStringAsFixed(1)} km/h',
              dark: true),
        ]),
      ]),
    );
  }
}

class _GnssBadge extends StatelessWidget {
  const _GnssBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AirspaceTheme.lime,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w600)),
      );
}

class _OperationalWeatherCard extends StatelessWidget {
  const _OperationalWeatherCard({required this.weather});
  final _WeatherSnapshot? weather;

  @override
  Widget build(BuildContext context) => Container(
        height: 145,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(PhosphorIconsRegular.gauge, size: 18),
            SizedBox(width: 7),
            Text('Datos para la operación',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const Spacer(),
          Row(children: [
            _FlightDatum(
                label: 'Presión',
                value: weather == null
                    ? '--'
                    : '${weather!.pressure.round()} hPa'),
            _FlightDatum(
                label: 'Nubosidad',
                value: weather == null
                    ? '--'
                    : '${weather!.cloudCover.round()}%'),
            _FlightDatum(
                label: 'Precipitación',
                value: weather == null
                    ? '--'
                    : '${weather!.precipitationChance.round()}%'),
          ]),
          const SizedBox(height: 15),
          Row(children: [
            _FlightDatum(
                label: 'Punto de rocío',
                value: weather == null
                    ? '--'
                    : '${weather!.dewPoint.round()}°'),
            _FlightDatum(
                label: 'Índice UV',
                value: weather == null ? '--' : '${weather!.uvIndex.round()}'),
            _FlightDatum(
                label: 'Humedad',
                value: weather == null
                    ? '--'
                    : '${weather!.humidity.round()}%'),
          ]),
        ]),
      );
}

class _FlightDatum extends StatelessWidget {
  const _FlightDatum({
    required this.label,
    required this.value,
    this.dark = false,
  });
  final String label;
  final String value;
  final bool dark;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: dark ? Colors.white38 : const Color(0xFF969994),
                  fontSize: 6)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  color: dark ? Colors.white : Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

class _KpIndexCard extends StatelessWidget {
  const _KpIndexCard({required this.data});
  final _GeomagneticSnapshot? data;

  Color get _statusColor {
    final kp = data?.kp ?? 0;
    if (kp >= 7) return const Color(0xFFFF5A52);
    if (kp >= 5) return const Color(0xFFFFB547);
    return AirspaceTheme.lime;
  }

  @override
  Widget build(BuildContext context) {
    final kp = data?.kp;
    final observed = data?.observedAt;
    final timeLabel = observed == null
        ? 'Esperando datos NOAA'
        : 'Actualizado ${observed.hour.toString().padLeft(2, '0')}:${observed.minute.toString().padLeft(2, '0')}';
    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(PhosphorIconsRegular.planet,
              size: 18, color: Color(0xFF161816)),
          const SizedBox(width: 7),
          const Text('Actividad geomagnética',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(data?.level ?? 'Sin datos',
                style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 9),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(kp == null ? '--' : kp.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 31, height: .9, fontWeight: FontWeight.w700)),
          const SizedBox(width: 5),
          const Padding(
            padding: EdgeInsets.only(bottom: 2),
            child: Text('Kp',
                style: TextStyle(color: Color(0xFF858883), fontSize: 9)),
          ),
          const Spacer(),
          Text(timeLabel,
              style: const TextStyle(color: Color(0xFF92958F), fontSize: 7)),
        ]),
        const SizedBox(height: 9),
        _KpScale(value: kp ?? 0),
        const SizedBox(height: 10),
        Row(children: [
          _KpMetric(label: 'Índice A', value: '${data?.aIndex ?? '--'}'),
          const SizedBox(width: 20),
          _KpMetric(
              label: 'Estaciones', value: '${data?.stationCount ?? '--'}'),
          const SizedBox(width: 20),
          Expanded(
            child: _KpMetric(
              label: 'Impacto GNSS',
              value: data?.operationLabel ?? 'Consultando',
            ),
          ),
        ]),
        const SizedBox(height: 7),
        Text(data?.operationMessage ?? 'Consultando actividad espacial…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF858883), fontSize: 7)),
      ]),
    );
  }
}

extension on _GeomagneticSnapshot {
  String get operationLabel {
    if (kp >= 7) return 'Alto';
    if (kp >= 5) return 'Moderado';
    return 'Bajo';
  }

  String get operationMessage =>
      '$operationLabel riesgo de degradación GNSS y brújula · Fuente NOAA SWPC';
}

class _KpMetric extends StatelessWidget {
  const _KpMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF9A9C98), fontSize: 6)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
        ],
      );
}

class _KpScale extends StatelessWidget {
  const _KpScale({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: List.generate(9, (index) {
              final active = value >= index + 1;
              final color = index < 4
                  ? AirspaceTheme.lime
                  : index < 6
                      ? const Color(0xFFFFB547)
                      : const Color(0xFFFF5A52);
              return Expanded(
                child: Container(
                  height: 7,
                  margin: EdgeInsets.only(right: index == 8 ? 0 : 2),
                  color: active ? color : const Color(0xFFE4E6E1),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 3),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('0 Tranquilo',
              style: TextStyle(color: Color(0xFFA0A29E), fontSize: 5)),
          Text('5 Tormenta',
              style: TextStyle(color: Color(0xFFA0A29E), fontSize: 5)),
          Text('9 Extremo',
              style: TextStyle(color: Color(0xFFA0A29E), fontSize: 5)),
        ]),
      ]);
}

class _LowBadge extends StatelessWidget {
  const _LowBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
        decoration: BoxDecoration(
          color: AirspaceTheme.lime,
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Text('Bajo', style: TextStyle(fontSize: 7)),
      );
}

class _CompassDial extends StatelessWidget {
  const _CompassDial({required this.speed, required this.direction});
  final double speed;
  final double direction;
  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 95,
        child: CustomPaint(
            painter: _ConditionsCompassPainter(speed, direction)),
      );
}

class _ConditionsCompassPainter extends CustomPainter {
  const _ConditionsCompassPainter(this.speed, this.direction);
  final double speed;
  final double direction;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * .39;
    final paint = Paint()
      ..color = const Color(0xFF454945)
      ..strokeWidth = .7;
    canvas.drawCircle(center, radius, paint..style = PaintingStyle.stroke);
    for (var index = 0; index < 24; index++) {
      final angle = index * math.pi / 12;
      canvas.drawLine(
        Offset(center.dx + math.cos(angle) * (radius - 4),
            center.dy + math.sin(angle) * (radius - 4)),
        Offset(center.dx + math.cos(angle) * radius,
            center.dy + math.sin(angle) * radius),
        paint,
      );
    }
    void drawCardinal(String label, Offset position) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: label == 'N' ? AirspaceTheme.lime : Colors.white70,
            fontSize: 7,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        position - Offset(painter.width / 2, painter.height / 2),
      );
    }

    drawCardinal('N', Offset(center.dx, center.dy - radius - 8));
    drawCardinal('E', Offset(center.dx + radius + 8, center.dy));
    drawCardinal('S', Offset(center.dx, center.dy + radius + 8));
    drawCardinal('W', Offset(center.dx - radius - 8, center.dy));

    final angle = (direction - 90) * math.pi / 180;
    final vector = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-vector.dy, vector.dx);
    final arrowStart = center + vector * 15;
    final arrowEnd = center + vector * (radius - 7);
    final arrowPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(arrowStart, arrowEnd, arrowPaint);
    canvas.drawLine(arrowEnd, arrowEnd - vector * 7 + normal * 4, arrowPaint);
    canvas.drawLine(arrowEnd, arrowEnd - vector * 7 - normal * 4, arrowPaint);

    final tailStart = center - vector * 15;
    final tailEnd = center - vector * (radius - 10);
    canvas.drawLine(tailStart, tailEnd, arrowPaint..color = Colors.white54);
    canvas.drawCircle(center, 2.3, Paint()..color = AirspaceTheme.lime);
    final text = TextPainter(
      text: TextSpan(
        text: '${speed.round()}\n',
        style: const TextStyle(color: Colors.white, fontSize: 19, height: .9),
        children: const [TextSpan(text: 'km/h', style: TextStyle(fontSize: 7))],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ConditionsCompassPainter oldDelegate) =>
      oldDelegate.speed != speed || oldDelegate.direction != direction;
}

class _LocationPending extends StatelessWidget {
  const _LocationPending({required this.error, required this.onRetry});
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF9CBFC8), Color(0xFFCBDDDA)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(PhosphorIconsRegular.crosshair,
              color: Colors.white, size: 34),
          const SizedBox(height: 14),
          Text(error ?? 'Obteniendo tu ubicación real…',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          if (error == null) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: AirspaceTheme.lime),
          ] else ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ]),
      );
}

class _AirspacePolygonData {
  const _AirspacePolygonData({
    required this.id,
    required this.title,
    required this.color,
    required this.points,
  });
  final String id;
  final String title;
  final Color color;
  final List<LatLng> points;
}

class _AirspacePointData {
  const _AirspacePointData({required this.id, required this.title, required this.point});
  final String id;
  final String title;
  final LatLng point;
}

class _AirspaceSnapshot {
  const _AirspaceSnapshot({
    required this.operation,
    required this.status,
    required this.reason,
    required this.maxAltitudeFeet,
    required this.maxAltitudeMeters,
    required this.restrictions,
    required this.polygons,
    required this.points,
    required this.notamUrl,
  });
  final String operation;
  final String status;
  final String reason;
  final int maxAltitudeFeet;
  final int maxAltitudeMeters;
  final List<String> restrictions;
  final List<_AirspacePolygonData> polygons;
  final List<_AirspacePointData> points;
  final String notamUrl;

  bool get prohibited => operation == 'prohibited';
  bool get conditional => operation == 'conditional' || operation == 'caution';

  factory _AirspaceSnapshot.fromJson(Map<String, dynamic> json) {
    final polygons = <_AirspacePolygonData>[];
    final points = <_AirspacePointData>[];
    final features = ((json['geojson'] as Map?)?['features'] as List?) ?? const [];
    var featureIndex = 0;
    for (final raw in features) {
      final feature = (raw as Map).cast<String, dynamic>();
      final geometry = (feature['geometry'] as Map? ?? const {}).cast<String, dynamic>();
      final properties =
          (feature['properties'] as Map? ?? const {}).cast<String, dynamic>();
      final title = '${properties['_layerTitle'] ?? 'Capa Aerocivil'}';
      final color = _hexColor('${properties['_color'] ?? '#F04444'}');
      final type = '${geometry['type']}';
      final coordinates = geometry['coordinates'];
      if (type == 'Point' && coordinates is List && coordinates.length >= 2) {
        points.add(_AirspacePointData(
          id: 'point-${featureIndex++}',
          title: title,
          point: LatLng((coordinates[1] as num).toDouble(),
              (coordinates[0] as num).toDouble()),
        ));
      } else {
        final rings = <List<dynamic>>[];
        if (type == 'Polygon' && coordinates is List) {
          rings.addAll(coordinates.whereType<List>());
        } else if (type == 'MultiPolygon' && coordinates is List) {
          for (final polygon in coordinates.whereType<List>()) {
            rings.addAll(polygon.whereType<List>());
          }
        }
        for (final ring in rings) {
          final path = ring.whereType<List>().where((pair) => pair.length >= 2).map(
                (pair) => LatLng((pair[1] as num).toDouble(),
                    (pair[0] as num).toDouble()),
              ).toList();
          if (path.length >= 3) {
            polygons.add(_AirspacePolygonData(
              id: 'polygon-${featureIndex++}',
              title: title,
              color: color,
              points: path,
            ));
          }
        }
      }
    }
    final intersections = json['intersections'] as List? ?? const [];
    return _AirspaceSnapshot(
      operation: '${json['operation'] ?? 'unknown'}',
      status: '${json['status'] ?? 'Estado no disponible'}',
      reason: '${json['reason'] ?? ''}',
      maxAltitudeFeet: (json['maxAltitudeFeet'] as num?)?.round() ?? 0,
      maxAltitudeMeters: (json['maxAltitudeMeters'] as num?)?.round() ?? 0,
      restrictions: intersections
          .map((item) =>
              '${(item as Map)['label'] ?? item['title'] ?? 'Restricción'}')
          .toSet()
          .toList(),
      polygons: polygons,
      points: points,
      notamUrl: '${json['notamUrl'] ?? ''}',
    );
  }
}

Color _hexColor(String value) {
  final normalized = value.replaceFirst('#', '');
  return Color(int.tryParse('FF$normalized', radix: 16) ?? 0xFFF04444);
}

class _AirspaceCard extends StatelessWidget {
  const _AirspaceCard({
    required this.location,
    required this.data,
    required this.deviceData,
    required this.loading,
    required this.error,
    required this.onRetry,
  });
  final LatLng location;
  final _AirspaceSnapshot? data;
  final _DeviceFlightData? deviceData;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  Color get statusColor => switch (data?.operation) {
        'prohibited' => const Color(0xFFE54444),
        'conditional' => const Color(0xFFF28A45),
        'caution' => const Color(0xFFE9B949),
        _ => const Color(0xFF24A260),
      };

  String get statusLabel => switch (data?.operation) {
        'prohibited' => 'NO PERMITIDO',
        'conditional' => 'CONDICIONADO',
        'caution' => 'PRECAUCIÓN',
        _ => loading ? 'CONSULTANDO' : 'PERMITIDO',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 42),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF9CBFC8), Color(0xFFCBDDDA)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
      ),
      child: Column(children: [
        const Text('Espacio aéreo',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(PhosphorIconsFill.navigationArrow,
              color: Colors.white, size: 12),
          const SizedBox(width: 5),
          Text(
              '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
        ]),
        const SizedBox(height: 21),
        Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 13),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(23)),
          child: Column(children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Estado del espacio aéreo',
                  style: TextStyle(color: Color(0xFF92958F), fontSize: 7)),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(13, 8, 10, 8),
              decoration: BoxDecoration(
                color: AirspaceTheme.lime,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Categoría abierta',
                          style: TextStyle(
                              fontSize: 17,
                              height: 1,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 3),
                      Text('Operación UAS · RAC 100',
                          style: TextStyle(
                              color: Color(0xFF42552F), fontSize: 7)),
                    ],
                  ),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C2619),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('RAC 100',
                        style: TextStyle(color: Colors.white, fontSize: 6)),
                  ),
                  const SizedBox(height: 4),
                  Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
            const SizedBox(height: 7),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(error ?? data?.status ?? 'Consultando capas oficiales…',
                  style: const TextStyle(
                      color: Color(0xFF898C87), fontSize: 7)),
            ),
            if (data != null && data!.reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(data!.reason,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 7,
                        fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFE8EAE6)),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(PhosphorIconsRegular.arrowUp,
                  size: 16, color: Color(0xFF27A35F)),
              const SizedBox(width: 7),
              const Text('Altitud máxima aplicable',
                  style: TextStyle(color: Color(0xFF858984), fontSize: 8)),
              const Spacer(),
              Text(
                  data == null
                      ? '--'
                      : '${data!.maxAltitudeFeet} ft · ${data!.maxAltitudeMeters} m AGL',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(
            child: _AirspaceMetric(
              icon: PhosphorIconsRegular.warning,
              value: '${data?.restrictions.length ?? 0}',
              label: 'Restricciones en tu ubicación',
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: _AirspaceMetric(
              icon: PhosphorIconsRegular.crosshair,
              loading: deviceData?.gnss == null,
              value: deviceData?.gnss == null
                  ? 'Buscando'
                  : '${deviceData!.gnss!.visible} sats',
              label: deviceData == null
                  ? 'Esperando señal GNSS'
                  : '${deviceData!.gnss?.used ?? 0} en uso · precisión ${deviceData!.horizontalAccuracy.toStringAsFixed(1)} m',
              dark: true,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () async {
            final url = data?.notamUrl ?? '';
            if (url.isEmpty) return;
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Enlace oficial de NOTAM copiado'),
              ));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Row(children: [
              Icon(PhosphorIconsRegular.copy,
                  size: 17, color: Color(0xFF24A260)),
              SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NOTAM oficiales',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600)),
                    Text('Copiar enlace de consulta de Aerocivil',
                        style: TextStyle(
                            color: Color(0xFF858984), fontSize: 7)),
                  ],
                ),
              ),
              Icon(PhosphorIconsRegular.caretRight,
                  size: 14, color: Color(0xFF858984)),
            ]),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Reintentar consulta')),
        ],
        const SizedBox(height: 11),
        _ProximityMap(
          key: ValueKey('${location.latitude},${location.longitude}'),
          location: location,
          data: data,
        ),
        if ((data?.restrictions.isNotEmpty ?? false)) ...[
          const SizedBox(height: 11),
          _RestrictionList(items: data!.restrictions),
        ],
      ]),
    );
  }
}

class _AirspaceMetric extends StatelessWidget {
  const _AirspaceMetric(
      {required this.icon,
      required this.value,
      required this.label,
      this.dark = false,
      this.loading = false});
  final IconData icon;
  final String value;
  final String label;
  final bool dark;
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
        height: 108,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF171917) : Colors.white,
          borderRadius: BorderRadius.circular(21),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              color: dark ? AirspaceTheme.lime : const Color(0xFFE8FFB9),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: Colors.black),
          ),
          const Spacer(),
          Row(children: [
            if (loading) ...[
              const SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 1.8, color: AirspaceTheme.lime),
              ),
              const SizedBox(width: 6),
            ],
            Text(value,
                style: TextStyle(
                    color: dark ? Colors.white : Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ]),
          Text(label,
              style: TextStyle(
                  color: dark ? Colors.white54 : const Color(0xFF858984),
                  fontSize: 7)),
        ]),
      );
}

class _ProximityMap extends StatelessWidget {
  const _ProximityMap({super.key, required this.location, required this.data});
  final LatLng location;
  final _AirspaceSnapshot? data;
  @override
  Widget build(BuildContext context) => Container(
        height: 360,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Text('Visor geográfico UAS',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            Spacer(),
            Text('Fuente · Aerocivil',
                style: TextStyle(color: Color(0xFF858984), fontSize: 7)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: location,
                  zoom: 13.5,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('pilot-location'),
                    position: location,
                    infoWindow: const InfoWindow(title: 'Tu ubicación'),
                  ),
                  ...?data?.points.map((item) => Marker(
                        markerId: MarkerId(item.id),
                        position: item.point,
                        infoWindow: InfoWindow(title: item.title),
                      )),
                },
                polygons: data?.polygons
                        .map((item) => Polygon(
                              polygonId: PolygonId(item.id),
                              points: item.points,
                              strokeColor: item.color,
                              strokeWidth: 2,
                              fillColor: item.color.withValues(alpha: .28),
                              consumeTapEvents: true,
                            ))
                        .toSet() ??
                    const {},
                zoomControlsEnabled: false,
                scrollGesturesEnabled: true,
                zoomGesturesEnabled: true,
                rotateGesturesEnabled: true,
                tiltGesturesEnabled: true,
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<EagerGestureRecognizer>(
                      () => EagerGestureRecognizer()),
                },
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: false,
                liteModeEnabled: false,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Wrap(spacing: 10, runSpacing: 4, children: [
            _MapLegendDot(color: Color(0xFFF04444), label: 'No vuelo'),
            _MapLegendDot(color: Color(0xFFF28A45), label: 'Aeropuertos'),
            _MapLegendDot(color: Color(0xFFC500FF), label: 'Infraestructura'),
            _MapLegendDot(color: Color(0xFF00A884), label: 'Aviación'),
          ]),
        ]),
      );
}

class _MapLegendDot extends StatelessWidget {
  const _MapLegendDot({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(label, style: const TextStyle(fontSize: 6)),
      ]);
}

class _RestrictionList extends StatelessWidget {
  const _RestrictionList({required this.items});
  final List<String> items;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Restricciones detectadas',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(children: [
                  const Icon(PhosphorIconsRegular.warning,
                      size: 12, color: Color(0xFFE54444)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(item, style: const TextStyle(fontSize: 8))),
                ]),
              )),
        ]),
      );
}

