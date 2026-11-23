import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import 'airspace_theme.dart';

class PreflightSummary extends StatelessWidget {
  const PreflightSummary({
    super.key,
    required this.name,
    required this.loading,
    required this.verification,
    required this.flights,
    required this.logs,
    required this.hours,
    required this.primaryDrone,
    required this.primaryModel,
    required this.primaryStatus,
    required this.primaryImage,
    required this.avatar,
    required this.avatarUrl,
    required this.onRefresh,
    required this.onOpenHangar,
    required this.onLogout,
  });

  final String name;
  final bool loading;
  final String verification;
  final int flights;
  final int logs;
  final double hours;
  final String primaryDrone;
  final String primaryModel;
  final String primaryStatus;
  final Uint8List? primaryImage;
  final Uint8List? avatar;
  final String? avatarUrl;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenHangar;
  final Future<void> Function() onLogout;

  String get _firstName =>
      name.trim().isEmpty ? 'Piloto' : name.trim().split(' ').first;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: const Color(0xFFF3F3F2),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Montserrat'),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          color: AirspaceTheme.ink,
          child: ListView(
            padding: EdgeInsets.fromLTRB(18, top + 12, 18, 132),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        Text('Pre-vuelo',
                            style: TextStyle(
                                fontFamily: 'Montserrat',
                                fontSize: 30,
                                height: 1,
                                fontStyle: FontStyle.italic,
                                letterSpacing: -.8)),
                        SizedBox(width: 8),
                        Icon(PhosphorIconsRegular.caretDown, size: 16),
                      ],
                    ),
                  ),
                  _CircleButton(
                    icon: PhosphorIconsRegular.bell,
                    onTap: () {},
                  ),
                  const SizedBox(width: 9),
                  GestureDetector(
                    onLongPress: onLogout,
                    child: CircleAvatar(
                      radius: 25,
                      backgroundColor: AirspaceTheme.ink,
                      backgroundImage: avatar != null
                          ? MemoryImage(avatar!)
                          : (avatarUrl == null || avatarUrl!.isEmpty
                              ? null
                              : NetworkImage(avatarUrl!)),
                      child: avatar == null &&
                              (avatarUrl == null || avatarUrl!.isEmpty)
                          ? Text(
                              _firstName.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 17),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 392,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFB9BDBC),
                      Color(0xFFDADDDC),
                      Color(0xFFF7F7F5),
                    ],
                    stops: [0, .48, 1],
                  ),
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x1A3F4242),
                        blurRadius: 24,
                        offset: Offset(0, 12)),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Hola,',
                                  style: TextStyle(
                                      color: Color(0xB3151716), fontSize: 13)),
                              Text(_firstName,
                                  style: const TextStyle(
                                      fontFamily: 'Montserrat',
                                      color: AirspaceTheme.ink,
                                      fontSize: 27,
                                      height: 1.05,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.5)),
                              const SizedBox(height: 5),
                              const Row(
                                children: [
                                  Icon(PhosphorIconsRegular.mapPin,
                                      color: AirspaceTheme.ink, size: 14),
                                  SizedBox(width: 4),
                                  Text('Colombia  ·  AHORA',
                                      style: TextStyle(
                                          color: AirspaceTheme.ink,
                                          fontSize: 10)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        _CircleButton(
                          icon: PhosphorIconsRegular.gear,
                          dark: true,
                          onTap: onOpenHangar,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: FractionallySizedBox(
                        widthFactor: .86,
                        child: Container(
                          height: 43,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: const Color(0x55709A9D),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 5,
                                child: Container(
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(22)),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text('DJI Air 3S',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700)),
                                      const Text('conectado',
                                          style: TextStyle(
                                              fontSize: 7,
                                              color: Color(0xFF27A85E))),
                                    ],
                                  ),
                                ),
                              ),
                              const Expanded(
                                flex: 4,
                                child: Center(
                                  child: Text('DJI Mini 4K',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 9)),
                                ),
                              ),
                              const Expanded(
                                flex: 4,
                                child: Center(
                                  child: Text('DJI Avata',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 9)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Image.asset(
                          'assets/dji consumer/drone_air_3s.png',
                          fit: BoxFit.contain,
                          width: 300,
                        ),
                      ),
                    ),
                    _FlightMetricsBar(
                      battery:
                          loading ? '--%' : '${(70 + flights).clamp(70, 99)}%',
                      minutes: '${(20 + hours ~/ 10).clamp(20, 35)} min',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: onOpenHangar,
                borderRadius: BorderRadius.circular(25),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(
                            value: .8,
                            minHeight: 5,
                            backgroundColor: Color(0xFFE6E8E5),
                            valueColor:
                                AlwaysStoppedAnimation(AirspaceTheme.lime)),
                      ),
                      const SizedBox(height: 10),
                      const Text('Checklist de pre-vuelo',
                          style: TextStyle(
                              fontSize: 10, color: AirspaceTheme.muted)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Text('Antes de despegar',
                              style: TextStyle(fontSize: 19)),
                          const SizedBox(width: 9),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: AirspaceTheme.lime,
                                borderRadius: BorderRadius.circular(16)),
                            child: const Text('4 / 5',
                                style: TextStyle(fontSize: 10)),
                          ),
                          const Spacer(),
                          const CircleAvatar(
                              radius: 19,
                              backgroundColor: Color(0xFFF1F3F0),
                              child:
                                  Icon(PhosphorIconsRegular.caretUp, size: 17)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const _WindConditionsCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton(
      {required this.icon, required this.onTap, this.dark = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) => Material(
        color: dark ? const Color(0x33617C7D) : Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
              width: 50,
              height: 50,
              child: Icon(icon,
                  color: dark ? Colors.white : AirspaceTheme.ink, size: 22)),
        ),
      );
}

class _FlightMetricsBar extends StatelessWidget {
  const _FlightMetricsBar({required this.battery, required this.minutes});
  final String battery;
  final String minutes;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 207,
        height: 49,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 4,
              child: _MetricLobe(
                width: 78,
                child: const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIconsRegular.gpsFix,
                          color: Colors.white, size: 15),
                      SizedBox(width: 4),
                      Text('14',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 4,
              child: _MetricLobe(
                width: 72,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Center(
                    child: Text(minutes,
                        maxLines: 1,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 61,
              top: 0,
              child: Container(
                width: 91,
                height: 49,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AirspaceTheme.lime,
                  borderRadius: BorderRadius.circular(27),
                  border: Border.all(color: const Color(0x5571847F), width: 6),
                ),
                child: Text(battery,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
}

class _MetricLobe extends StatelessWidget {
  const _MetricLobe({required this.width, required this.child});
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: 41,
        decoration: BoxDecoration(
          color: const Color(0xE05F706E),
          borderRadius: BorderRadius.circular(24),
        ),
        child: child,
      );
}

class _WindConditionsCard extends StatelessWidget {
  const _WindConditionsCard();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.center,
        child: FractionallySizedBox(
          widthFactor: 1,
          child: Container(
            height: 146,
            decoration: BoxDecoration(
              color: const Color(0xFF050605),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(children: [
              const Positioned(
                left: 16,
                top: 12,
                child: Text('Viento',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
              Positioned(
                right: 16,
                top: 11,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                  decoration: BoxDecoration(
                    color: AirspaceTheme.lime,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Bajo',
                      style:
                          TextStyle(fontSize: 8, fontWeight: FontWeight.w600)),
                ),
              ),
              const Positioned(
                left: 16,
                top: 40,
                width: 38,
                height: 91,
                child: CustomPaint(painter: _AltitudeScalePainter()),
              ),
              const Positioned(
                left: 61,
                top: 48,
                width: 104,
                child: Column(children: [
                  Text('Altitud máxima segura',
                      maxLines: 1,
                      style: TextStyle(color: Colors.white54, fontSize: 6)),
                  SizedBox(height: 3),
                  Text('130m',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          height: 1,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
              const Positioned(
                left: 58,
                top: 102,
                width: 61,
                child: Column(children: [
                  Text('Ráfagas',
                      style: TextStyle(color: Colors.white38, fontSize: 6)),
                  SizedBox(height: 2),
                  Text('18 km/h',
                      style: TextStyle(color: Colors.white, fontSize: 9)),
                ]),
              ),
              const Positioned(
                left: 119,
                top: 102,
                width: 53,
                child: Column(children: [
                  Text('Visibilidad',
                      style: TextStyle(color: Colors.white38, fontSize: 6)),
                  SizedBox(height: 2),
                  Text('Baja',
                      style: TextStyle(color: Colors.white, fontSize: 9)),
                ]),
              ),
              const Positioned(
                right: 7,
                top: 38,
                width: 110,
                height: 96,
                child: CustomPaint(painter: _CompassPainter()),
              ),
            ]),
          ),
        ),
      );
}

// ignore: unused_element
class _LegacyWindConditionsCard extends StatelessWidget {
  const _LegacyWindConditionsCard();

  @override
  Widget build(BuildContext context) => Container(
        height: 158,
        padding: const EdgeInsets.fromLTRB(17, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF050605),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Column(children: [
          Row(children: [
            const Text('Viento',
                style: TextStyle(color: Colors.white, fontSize: 14)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                color: AirspaceTheme.lime,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Bajo',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 4),
          Expanded(
            child: Row(children: [
              const SizedBox(
                width: 42,
                child: CustomPaint(painter: _AltitudeScalePainter()),
              ),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Altitud máxima segura',
                        style: TextStyle(color: Colors.white54, fontSize: 7)),
                    SizedBox(height: 2),
                    Text('130m',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _WindValue(value: '18 km/h', label: 'Ráfagas'),
                        _WindValue(value: 'Baja', label: 'Visibilidad'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width: 118,
                child: CustomPaint(painter: _CompassPainter()),
              ),
            ]),
          ),
        ]),
      );
}

class _WindValue extends StatelessWidget {
  const _WindValue({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 6)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 9)),
      ]);
}

class _AltitudeScalePainter extends CustomPainter {
  const _AltitudeScalePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5C625E)
      ..strokeWidth = .7;
    for (var index = 0; index < 22; index++) {
      final y = 5 + index * ((size.height - 10) / 21);
      final length = index % 5 == 0 ? 17.0 : 9.0;
      canvas.drawLine(Offset(0, y), Offset(length, y), paint);
    }
    final markerY = size.height * .48;
    canvas.drawLine(
        Offset(0, markerY), Offset(25, markerY), Paint()..color = Colors.white);
    const text = TextSpan(
        text: '130m', style: TextStyle(color: Colors.white70, fontSize: 6));
    final painter = TextPainter(text: text, textDirection: TextDirection.ltr)
      ..layout();
    painter.paint(canvas, Offset(26, markerY - 4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .37;
    final ring = Paint()
      ..color = const Color(0xFF252A27)
      ..strokeWidth = .65
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, ring);
    for (var index = 0; index < 48; index++) {
      final angle = index * math.pi / 24;
      final outer = Offset(center.dx + math.cos(angle) * radius,
          center.dy + math.sin(angle) * radius);
      final innerRadius = radius - (index % 6 == 0 ? 5 : 2.2);
      final inner = Offset(center.dx + math.cos(angle) * innerRadius,
          center.dy + math.sin(angle) * innerRadius);
      canvas.drawLine(inner, outer, ring);
    }
    _centerLabel(canvas, 'N', Offset(center.dx, center.dy - radius - 7), 7);
    _centerLabel(canvas, 'S', Offset(center.dx, center.dy + radius + 7), 7);
    _centerLabel(canvas, 'W', Offset(center.dx - radius - 8, center.dy), 7);
    _centerLabel(canvas, 'E', Offset(center.dx + radius + 8, center.dy), 7);
    _centerLabel(canvas, '24', Offset(center.dx, center.dy - 5), 18);
    _centerLabel(canvas, 'km/h', Offset(center.dx, center.dy + 10), 6,
        color: Colors.white70);

    final directionPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final westTip = Offset(center.dx - radius + 1, center.dy);
    final westBase = Offset(westTip.dx + 10, westTip.dy);
    canvas.drawLine(
      westBase,
      Offset(westBase.dx + 10, westBase.dy),
      directionPaint,
    );
    final arrow = Path()
      ..moveTo(westTip.dx, westTip.dy)
      ..lineTo(westBase.dx, westBase.dy - 4)
      ..lineTo(westBase.dx, westBase.dy + 4)
      ..close();
    canvas.drawPath(arrow, Paint()..color = Colors.white);

    final eastStart = Offset(center.dx + radius - 18, center.dy);
    final eastEnd = Offset(center.dx + radius - 2, center.dy);
    canvas.drawLine(eastStart, eastEnd, directionPaint);
    canvas.drawCircle(eastEnd, 2.2, Paint()..color = const Color(0xFF050605));
    canvas.drawCircle(
        eastEnd, 2.2, directionPaint..style = PaintingStyle.stroke);
  }

  void _centerLabel(Canvas canvas, String text, Offset center, double size,
      {Color color = Colors.white}) {
    final painter = TextPainter(
      text:
          TextSpan(text: text, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
