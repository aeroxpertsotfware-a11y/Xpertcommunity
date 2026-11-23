import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_icons/phosphor_icons.dart';

import 'airspace_theme.dart';

const _logsApi = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://xpertcommunity-production.up.railway.app',
);

class FlightLogsPage extends StatefulWidget {
  const FlightLogsPage({super.key});

  @override
  State<FlightLogsPage> createState() => _FlightLogsPageState();
}

class _FlightLogsPageState extends State<FlightLogsPage> {
  bool _loading = true;
  int _flights = 0;
  int _logs = 0;
  double _hours = 0;
  double _maxAltitude = 0;
  Uint8List? _avatar;
  List<_LogEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await user.getIdToken();
      final responses = await Future.wait([
        http.get(Uri.parse('$_logsApi/api/hangar'), headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        }),
        http.get(Uri.parse('$_logsApi/api/profiles/${user.uid}')),
      ]);
      final hangar = responses[0].statusCode == 200
          ? jsonDecode(utf8.decode(responses[0].bodyBytes))
              as Map<String, dynamic>
          : <String, dynamic>{};
      final profile = responses[1].statusCode == 200
          ? jsonDecode(utf8.decode(responses[1].bodyBytes))
              as Map<String, dynamic>
          : <String, dynamic>{};
      final aircraft = hangar['aircraft'] as List? ?? const [];
      final entries = <_LogEntry>[];
      var flights = 0;
      var hours = 0.0;
      for (final item in aircraft) {
        final drone = (item as Map).cast<String, dynamic>();
        flights += (drone['flights'] as num?)?.toInt() ?? 0;
        hours += (drone['flightHours'] as num?)?.toDouble() ?? 0;
        for (final rawLog in drone['logs'] as List? ?? const []) {
          final log = (rawLog as Map).cast<String, dynamic>();
          entries.add(_LogEntry(
            name: '${log['name'] ?? 'Log de vuelo'}',
            drone: '${drone['name'] ?? drone['model'] ?? 'UAS'}',
            date:
                DateTime.tryParse('${log['addedAt'] ?? ''}') ?? DateTime.now(),
          ));
        }
      }
      entries.sort((a, b) => b.date.compareTo(a.date));
      Uint8List? avatar;
      if ((profile['images'] as Map?)?['avatar'] != null) {
        final image = await http.get(
          Uri.parse('$_logsApi/api/profiles/${user.uid}/images/avatar'),
        );
        if (image.statusCode == 200) avatar = image.bodyBytes;
      }
      if (!mounted) return;
      setState(() {
        _flights = flights;
        _hours = hours;
        _logs = entries.length;
        _maxAltitude = 0;
        _entries = entries;
        _avatar = avatar;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF2F2F1),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: Colors.black,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
              children: [
                _Header(avatar: _avatar),
                const SizedBox(height: 18),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                        child: CircularProgressIndicator(color: Colors.black)),
                  )
                else ...[
                  _MetricsCard(
                    flights: _flights,
                    hours: _hours,
                    altitude: _maxAltitude,
                    logs: _logs,
                  ),
                  const SizedBox(height: 17),
                  Row(children: [
                    const Expanded(
                      child: Text('Vuelos este año',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Text('${DateTime.now().year}',
                        style: const TextStyle(
                            color: Color(0xFF888B87), fontSize: 10)),
                    const SizedBox(width: 4),
                    const Icon(PhosphorIconsRegular.caretUp, size: 13),
                  ]),
                  const SizedBox(height: 9),
                  _ActivityCard(activity: math.max(_flights, _logs)),
                  const SizedBox(height: 24),
                  Row(children: [
                    const Expanded(
                      child: Text('Registro de vuelos',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -.7)),
                    ),
                    _HeaderIcon(
                        icon: PhosphorIconsRegular.funnel, onTap: () {}),
                    const SizedBox(width: 8),
                    _HeaderIcon(
                        icon: PhosphorIconsRegular.magnifyingGlass,
                        onTap: () {}),
                  ]),
                  const SizedBox(height: 13),
                  if (_entries.isEmpty)
                    const _FlightLogCard(
                      title: 'Vuelo de ejemplo',
                      subtitle: 'Agrega un log desde tu UAS',
                      demo: true,
                      seed: 2,
                    )
                  else
                    ..._entries.take(8).toList().asMap().entries.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _FlightLogCard(
                              title: item.value.name,
                              subtitle:
                                  '${item.value.drone} · ${_date(item.value.date)}',
                              seed: item.key,
                            ),
                          ),
                        ),
                ],
              ],
            ),
          ),
        ),
      );

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _Header extends StatelessWidget {
  const _Header({required this.avatar});
  final Uint8List? avatar;

  @override
  Widget build(BuildContext context) => Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Row(children: [
            Icon(PhosphorIconsRegular.caretLeft, size: 17),
            SizedBox(width: 7),
            Text('Logbook',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
            SizedBox(width: 7),
            Icon(PhosphorIconsRegular.caretDown, size: 13),
          ]),
        ),
        const Spacer(),
        _HeaderIcon(icon: PhosphorIconsRegular.bell, onTap: () {}),
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

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(width: 43, height: 43, child: Icon(icon, size: 18)),
        ),
      );
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({
    required this.flights,
    required this.hours,
    required this.altitude,
    required this.logs,
  });
  final int flights;
  final double hours;
  final double altitude;
  final int logs;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Column(children: [
          _MetricBar(value: '$flights', label: 'Vuelos totales', width: 1),
          _MetricBar(
              value: '${hours.toStringAsFixed(hours < 10 ? 1 : 0)}h',
              label: 'Tiempo de vuelo',
              width: .91),
          _MetricBar(
              value: '${altitude.toStringAsFixed(0)}m',
              label: 'Altitud máxima',
              width: .67),
          _MetricBar(value: '$logs', label: 'Logs cargados', width: .52),
        ]),
      );
}

class _MetricBar extends StatelessWidget {
  const _MetricBar(
      {required this.value, required this.label, required this.width});
  final String value;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: width,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: AirspaceTheme.lime,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 8)),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.activity});
  final int activity;

  @override
  Widget build(BuildContext context) => Container(
        height: 132,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF090B0A),
          borderRadius: BorderRadius.circular(22),
        ),
        child: CustomPaint(painter: _HeatmapPainter(activity)),
      );
}

class _HeatmapPainter extends CustomPainter {
  const _HeatmapPainter(this.activity);
  final int activity;

  @override
  void paint(Canvas canvas, Size size) {
    const rows = 7;
    const columns = 24;
    const gap = 3.2;
    final cell = math.min((size.width - gap * (columns - 1)) / columns,
        (size.height - gap * (rows - 1)) / rows);
    for (var column = 0; column < columns; column++) {
      for (var row = 0; row < rows; row++) {
        final signal = (column * 17 + row * 11 + activity * 3) % 23;
        final active = signal < math.min(15, 3 + activity ~/ 2);
        final color = active
            ? Color.lerp(const Color(0xFF25301D), AirspaceTheme.lime,
                .25 + (signal % 6) * .12)!
            : const Color(0xFF171A17);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
                column * (cell + gap), row * (cell + gap), cell, cell),
            const Radius.circular(2),
          ),
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) =>
      oldDelegate.activity != activity;
}

class _FlightLogCard extends StatelessWidget {
  const _FlightLogCard({
    required this.title,
    required this.subtitle,
    required this.seed,
    this.demo = false,
  });
  final String title;
  final String subtitle;
  final int seed;
  final bool demo;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 130,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(children: [
                Positioned.fill(
                    child: CustomPaint(painter: _RoutePainter(seed))),
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: AirspaceTheme.lime,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(demo ? 'Ejemplo' : 'Ruta GPS',
                        style: const TextStyle(
                            fontSize: 8, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(subtitle,
              style: const TextStyle(color: Color(0xFF858884), fontSize: 9)),
        ]),
      );
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter(this.seed);
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFE7E8E5));
    final road = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (var i = 0; i < 5; i++) {
      final y = 15.0 + i * 27;
      canvas.drawPath(
        Path()
          ..moveTo(-10, y)
          ..quadraticBezierTo(size.width * .3, y - 28, size.width * .55, y + 4)
          ..quadraticBezierTo(size.width * .76, y + 25, size.width + 10, y - 8),
        road,
      );
    }
    final route = Path()
      ..moveTo(size.width * .31, size.height * .18)
      ..cubicTo(size.width * .55, size.height * .05, size.width * .63,
          size.height * .25, size.width * .48, size.height * .46)
      ..cubicTo(size.width * .34, size.height * .68, size.width * .68,
          size.height * .82, size.width * .55, size.height * .91)
      ..cubicTo(size.width * .42, size.height, size.width * .25,
          size.height * .65, size.width * .31, size.height * .18);
    canvas.drawPath(
        route,
        Paint()
          ..color = const Color(0xFF646B38)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.5);
    canvas.drawCircle(Offset(size.width * .31, size.height * .18), 6,
        Paint()..color = AirspaceTheme.lime);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.seed != seed;
}

class _LogEntry {
  const _LogEntry(
      {required this.name, required this.drone, required this.date});
  final String name;
  final String drone;
  final DateTime date;
}
