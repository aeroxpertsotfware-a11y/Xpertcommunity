import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_icons/phosphor_icons.dart';

import 'app_feedback.dart';
import 'airspace_theme.dart';
import 'drone_hangar_page.dart';
import 'flight_logs_page.dart';
import 'flight_conditions_page.dart';
import 'preflight_summary.dart';
import 'career_application_page.dart';

const _api = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://xpertcommunity-production.up.railway.app',
);

// Se conserva el flujo profesional para retomarlo más adelante, pero por el
// momento no se muestra ni se promociona desde el perfil.
const _showCareerFeatures = false;

class IndependentPilotHomePage extends StatefulWidget {
  const IndependentPilotHomePage({super.key});

  @override
  State<IndependentPilotHomePage> createState() =>
      _IndependentPilotHomePageState();
}

class _IndependentPilotHomePageState extends State<IndependentPilotHomePage> {
  int _section = 0;
  bool _checkingCareer = false;

  Future<void> _openHangar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DroneHangarPage(userId: uid)),
    );
  }

  Future<void> _openLogs() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FlightLogsPage()),
    );
  }

  Future<void> _openConditions() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FlightConditionsPage()),
    );
  }

  Future<void> _openAirspace() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const FlightConditionsPage(airspaceOnly: true),
      ),
    );
  }

  void _openProfile() {
    setState(() => _section = 1);
    if (_showCareerFeatures) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _offerCareerInProfile());
    }
  }

  Future<void> _offerCareerInProfile() async {
    if (!mounted || _checkingCareer) return;
    _checkingCareer = true;
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final response = await http.get(
        Uri.parse('$_api/api/career/me'),
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (response.statusCode != 200) {
        await _showBasicCareerOffer();
        return;
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      final application = body['application'] as Map?;
      final status = '${application?['status'] ?? ''}';
      if (status == 'approved') return;
      final hasDraft = application != null && status == 'draft';
      final submitted = status == 'submitted';
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AirspaceTheme.lime,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  submitted
                      ? PhosphorIconsRegular.clockCountdown
                      : PhosphorIconsRegular.briefcase,
                  size: 23,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                submitted
                    ? 'Tu postulación está en revisión'
                    : hasDraft
                        ? 'Tienes una postulación por completar'
                        : '¿Quieres postularte a una empresa?',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              Text(
                submitted
                    ? 'Aún no tienes un cargo asociado. Puedes consultar el estado y los requisitos enviados.'
                    : 'Revisa los requisitos para ser Piloto UAS, Jefe de Pilotos o Gerente SMS.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Color(0xFF737873)),
              ),
              const SizedBox(height: 17),
              FilledButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const CareerApplicationPage(),
                  ));
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(submitted
                    ? 'Ver estado'
                    : hasDraft
                        ? 'Continuar postulación'
                        : 'Explorar cargos'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                style: TextButton.styleFrom(foregroundColor: Colors.black54),
                child: const Text('Cerrar'),
              ),
            ]),
          ),
        ),
      );
    } catch (_) {
      if (mounted) await _showBasicCareerOffer();
    } finally {
      _checkingCareer = false;
    }
  }

  Future<void> _showBasicCareerOffer() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AirspaceTheme.lime,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(PhosphorIconsRegular.briefcase, size: 23),
            ),
            const SizedBox(height: 14),
            const Text(
              '¿Quieres postularte a una empresa?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 7),
            const Text(
              'Revisa los requisitos para ser Piloto UAS, Jefe de Pilotos o Gerente SMS.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Color(0xFF737873)),
            ),
            const SizedBox(height: 17),
            FilledButton(
              onPressed: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const CareerApplicationPage(),
                ));
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text('Explorar cargos'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              style: TextButton.styleFrom(foregroundColor: Colors.black54),
              child: const Text('Cerrar'),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AirspaceTheme.canvas,
        body: IndexedStack(
          index: _section,
          children: [
            const _PilotDashboard(),
            _ProfessionalProfile(onBack: () => setState(() => _section = 0)),
          ],
        ),
        extendBody: true,
        bottomNavigationBar: _PilotNavigation(
          profileActive: _section == 1,
          onProfile: _openProfile,
          onAirspace: _openAirspace,
          onBitacora: _openHangar,
          onLogs: _openLogs,
          onUas: _openHangar,
          onConditions: _openConditions,
          onSummary: () => setState(() => _section = 0),
        ),
      );
}

class _PilotNavigation extends StatelessWidget {
  const _PilotNavigation({
    required this.profileActive,
    required this.onProfile,
    required this.onAirspace,
    required this.onBitacora,
    required this.onLogs,
    required this.onUas,
    required this.onConditions,
    required this.onSummary,
  });

  final bool profileActive;
  final VoidCallback onProfile;
  final VoidCallback onAirspace;
  final VoidCallback onBitacora;
  final VoidCallback onLogs;
  final VoidCallback onUas;
  final VoidCallback onConditions;
  final VoidCallback onSummary;

  @override
  Widget build(BuildContext context) => SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 68,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(36),
                  border: Border.all(color: Colors.white),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1C294B4E),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _NavDestination(
                      icon: PhosphorIconsRegular.mapTrifold,
                      label: 'Espacio',
                      active: false,
                      onTap: onAirspace,
                    ),
                    _NavDestination(
                      icon: PhosphorIconsRegular.bookOpenText,
                      label: 'Bitácora',
                      active: false,
                      onTap: onBitacora,
                    ),
                    _NavDestination(
                      icon: PhosphorIconsRegular.fileText,
                      label: 'Logs',
                      active: false,
                      onTap: onLogs,
                    ),
                    _NavDestination(
                      icon: PhosphorIconsRegular.airplaneTilt,
                      label: 'UAS',
                      active: false,
                      onTap: onUas,
                    ),
                    _NavDestination(
                      icon: PhosphorIconsRegular.cloudSun,
                      label: 'Clima',
                      active: false,
                      onTap: onConditions,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 9),
            Material(
              color: profileActive
                  ? Colors.black.withValues(alpha: .9)
                  : Colors.white.withValues(alpha: .72),
              shape: const CircleBorder(side: BorderSide(color: Colors.white)),
              elevation: 5,
              shadowColor: const Color(0x33294B4E),
              child: InkWell(
                onTap: profileActive ? onSummary : onProfile,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: Icon(
                    PhosphorIconsRegular.userCircle,
                    size: 26,
                    color: profileActive ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _NavDestination extends StatelessWidget {
  const _NavDestination({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(29),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: active ? AirspaceTheme.lime : Colors.transparent,
              borderRadius: BorderRadius.circular(29),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 21, weight: .8),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 8,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _PilotDashboard extends StatefulWidget {
  const _PilotDashboard();

  @override
  State<_PilotDashboard> createState() => _PilotDashboardState();
}

class _PilotDashboardState extends State<_PilotDashboard> {
  bool _loading = true;
  int _aircraft = 0;
  int _flights = 0;
  int _logs = 0;
  double _hours = 0;
  String _name = 'Piloto';
  String _verification = 'Perfil incompleto';
  String _primaryDrone = 'Agrega tu primera aeronave';
  String _primaryModel = 'Tu equipo principal aparecerá aquí';
  String _primaryStatus = 'Sin registrar';
  Uint8List? _primaryImage;
  Uint8List? _avatar;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _headers() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('$_api/api/profiles/${user.uid}')),
        http.get(Uri.parse('$_api/api/hangar'), headers: await _headers()),
      ]);
      final profile = responses[0].statusCode == 200
          ? jsonDecode(utf8.decode(responses[0].bodyBytes))
              as Map<String, dynamic>
          : <String, dynamic>{};
      final hangar = responses[1].statusCode == 200
          ? jsonDecode(responses[1].body) as Map<String, dynamic>
          : <String, dynamic>{};
      final drones = (hangar['aircraft'] as List? ?? const []);
      final documents = profile['documents'] as Map<String, dynamic>?;
      Uint8List? avatar;
      if ((profile['images'] as Map?)?['avatar'] != null) {
        final avatarResponse = await http.get(
          Uri.parse('$_api/api/profiles/${user.uid}/images/avatar'),
        );
        if (avatarResponse.statusCode == 200) {
          avatar = avatarResponse.bodyBytes;
        }
      }
      if (!mounted) return;
      setState(() {
        _name = '${profile['name'] ?? user.displayName ?? 'Piloto'}';
        _avatar = avatar;
        _aircraft = drones.length;
        _flights = drones.fold<int>(
          0,
          (total, item) =>
              total + (((item as Map)['flights'] as num?)?.toInt() ?? 0),
        );
        _hours = drones.fold<double>(
          0,
          (total, item) =>
              total + (((item as Map)['flightHours'] as num?)?.toDouble() ?? 0),
        );
        _logs = drones.fold<int>(
          0,
          (total, item) =>
              total + (((item as Map)['logs'] as List?)?.length ?? 0),
        );
        if (drones.isNotEmpty) {
          final primary = (drones.first as Map).cast<String, dynamic>();
          _primaryDrone = '${primary['name'] ?? 'Mi aeronave'}';
          _primaryModel =
              '${primary['manufacturer'] ?? ''} ${primary['model'] ?? ''}'
                  .trim();
          _primaryStatus = '${primary['status'] ?? 'Activo'}';
          final image = primary['imageBase64'] as String?;
          if (image != null && image.isNotEmpty) {
            try {
              _primaryImage = base64Decode(image);
            } catch (_) {
              _primaryImage = null;
            }
          }
        }
        final resume = documents?['resume'] != null;
        final cipu = documents?['cipu'] != null;
        _verification = resume && cipu
            ? 'Documentos listos para verificación'
            : resume || cipu
                ? 'Verificación en progreso'
                : 'Perfil incompleto';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openHangar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DroneHangarPage(userId: uid)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => PreflightSummary(
        name: _name,
        loading: _loading,
        verification: _verification,
        flights: _flights,
        logs: _logs,
        hours: _hours,
        primaryDrone: _primaryDrone,
        primaryModel: _primaryModel,
        primaryStatus: _primaryStatus,
        primaryImage: _primaryImage,
        avatar: _avatar,
        avatarUrl: FirebaseAuth.instance.currentUser?.photoURL,
        onRefresh: _load,
        onOpenHangar: _openHangar,
        onLogout: () async {
          await GoogleSignIn.instance.signOut();
          await FirebaseAuth.instance.signOut();
        },
      );

  // ignore: unused_element
  Widget _buildLegacy(BuildContext context) => SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: Colors.black,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BITÁCORA PERSONAL',
                          style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.5,
                              color: Color(0xFF777777))),
                      const SizedBox(height: 5),
                      Text('Hola, ${_name.split(' ').first}',
                          style: const TextStyle(
                              fontSize: 29, fontWeight: FontWeight.w400)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar sesión',
                  onPressed: () async {
                    await GoogleSignIn.instance.signOut();
                    await FirebaseAuth.instance.signOut();
                  },
                  icon: const Icon(PhosphorIconsRegular.signOut),
                ),
              ]),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AirspaceTheme.skyGradient,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AirspaceTheme.lime,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(PhosphorIconsRegular.shieldCheck,
                            color: AirspaceTheme.ink, size: 24),
                      ),
                      const SizedBox(height: 16),
                      const Text('Estado profesional',
                          style: TextStyle(
                              color: AirspaceTheme.ink, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(_loading ? 'Consultando…' : _verification,
                          style: const TextStyle(
                              color: AirspaceTheme.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w400)),
                    ]),
              ),
              const SizedBox(height: 18),
              Row(children: [
                _Metric(value: '$_aircraft', label: 'Drones'),
                const SizedBox(width: 10),
                _Metric(value: '$_flights', label: 'Vuelos'),
                const SizedBox(width: 10),
                _Metric(value: _hours.toStringAsFixed(1), label: 'Horas'),
              ]),
              const SizedBox(height: 28),
              const Text('Gestión de vuelo',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
              const SizedBox(height: 12),
              _ActionCard(
                icon: PhosphorIconsRegular.airplaneTilt,
                title: 'Mi hangar',
                subtitle: 'Aeronaves, estado y horas acumuladas',
                onTap: _openHangar,
              ),
              _ActionCard(
                icon: PhosphorIconsRegular.bookOpenText,
                title: 'Bitácoras de vuelo',
                subtitle: '$_logs archivos registrados en tus aeronaves',
                onTap: _openHangar,
              ),
              _ActionCard(
                icon: PhosphorIconsRegular.wrench,
                title: 'Mantenimiento',
                subtitle: 'Control técnico de tus equipos',
                onTap: _openHangar,
              ),
            ],
          ),
        ),
      );
}

// Conservado temporalmente como referencia del dashboard anterior.
// ignore: unused_element
class _AirspaceDashboard extends StatelessWidget {
  const _AirspaceDashboard({
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
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenHangar;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        color: AirspaceTheme.ink,
        child: ListView(padding: EdgeInsets.zero, children: [
          Container(
            height: 238,
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.paddingOf(context).top + 16, 20, 34),
            decoration: const BoxDecoration(
              gradient: AirspaceTheme.skyGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
            ),
            child: Column(children: [
              Row(children: [
                const Expanded(
                  child: Text('AeroXpert\nFlight deck',
                      style: TextStyle(fontSize: 13, height: 1.1)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .68),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(children: [
                    Icon(PhosphorIconsFill.navigationArrow, size: 13),
                    SizedBox(width: 5),
                    Text('Mi operación', style: TextStyle(fontSize: 10)),
                  ]),
                ),
                IconButton(
                  onPressed: onLogout,
                  icon: const Icon(PhosphorIconsRegular.signOut),
                ),
              ]),
              const Spacer(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Hola, ${name.split(' ').first}',
                    style: const TextStyle(fontSize: 36, height: 1)),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Todo listo para tu próxima operación',
                    style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AirspaceTheme.surface,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x11000000),
                          blurRadius: 20,
                          offset: Offset(0, 8)),
                    ],
                  ),
                  child: Row(children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AirspaceTheme.lime,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(PhosphorIconsRegular.shieldCheck),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Estado profesional',
                              style: TextStyle(
                                  fontSize: 10, color: AirspaceTheme.muted)),
                          const SizedBox(height: 4),
                          Text(loading ? 'Consultando…' : verification,
                              style: const TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                    const Icon(PhosphorIconsRegular.caretRight),
                  ]),
                ),
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(
                    flex: 6,
                    child: Container(
                      height: 154,
                      padding: const EdgeInsets.all(17),
                      decoration: BoxDecoration(
                        gradient: AirspaceTheme.darkGradient,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(PhosphorIconsRegular.timer,
                                size: 18, color: AirspaceTheme.lime),
                            Spacer(),
                            Text('TOTAL',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 9)),
                          ]),
                          const Spacer(),
                          Text(hours.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 34)),
                          const Text('horas de vuelo',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: Column(children: [
                      _BentoMetric(
                          value: '$flights',
                          label: 'Vuelos',
                          color: AirspaceTheme.limeSoft),
                      const SizedBox(height: 10),
                      _BentoMetric(
                          value: '$logs',
                          label: 'Bitácoras',
                          color: AirspaceTheme.surface),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                InkWell(
                  onTap: onOpenHangar,
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    height: 260,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: AirspaceTheme.skyGradient,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Stack(children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('AERONAVE PRINCIPAL',
                                      style: TextStyle(
                                          fontSize: 9, letterSpacing: 1.2)),
                                  const SizedBox(height: 5),
                                  Text(primaryDrone,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 20)),
                                  Text(primaryModel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 10)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AirspaceTheme.lime,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(primaryStatus,
                                  style: const TextStyle(fontSize: 9)),
                            ),
                          ]),
                      Positioned.fill(
                        top: 58,
                        child: primaryImage == null
                            ? const Icon(PhosphorIconsRegular.airplaneTilt,
                                size: 112, color: AirspaceTheme.ink)
                            : Image.memory(primaryImage!,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium),
                      ),
                      const Positioned(
                        right: 0,
                        bottom: 0,
                        child: Row(children: [
                          Text('Abrir hangar', style: TextStyle(fontSize: 10)),
                          SizedBox(width: 5),
                          Icon(PhosphorIconsRegular.arrowRight, size: 16),
                        ]),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _CompactAction(
                      icon: PhosphorIconsRegular.bookOpenText,
                      title: 'Bitácoras',
                      subtitle: '$logs archivos',
                      onTap: onOpenHangar,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CompactAction(
                      icon: PhosphorIconsRegular.wrench,
                      title: 'Técnico',
                      subtitle: 'Mantenimiento',
                      onTap: onOpenHangar,
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      );
}

class _BentoMetric extends StatelessWidget {
  const _BentoMetric(
      {required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white),
        ),
        child: Row(children: [
          Text(value, style: const TextStyle(fontSize: 26)),
          const Spacer(),
          Text(label,
              style: const TextStyle(fontSize: 9, color: AirspaceTheme.muted)),
        ]),
      );
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AirspaceTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AirspaceTheme.line),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 23),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontSize: 14)),
            Text(subtitle,
                style:
                    const TextStyle(fontSize: 9, color: AirspaceTheme.muted)),
          ]),
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: BoxDecoration(
            color: AirspaceTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AirspaceTheme.line),
          ),
          child: Column(children: [
            Text(value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF777777))),
          ]),
        ),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AirspaceTheme.surface,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: AirspaceTheme.line),
        ),
        child: ListTile(
          onTap: onTap,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AirspaceTheme.limeSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon),
          ),
          title: Text(title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w400)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
          trailing: const Icon(PhosphorIconsRegular.caretRight),
        ),
      );
}

class _ProfessionalProfile extends StatefulWidget {
  const _ProfessionalProfile({required this.onBack});

  final VoidCallback onBack;

  @override
  State<_ProfessionalProfile> createState() => _ProfessionalProfileState();
}

class _ProfessionalProfileState extends State<_ProfessionalProfile> {
  Map<String, dynamic> _profile = const {};
  Uint8List? _avatar;
  Uint8List? _cover;
  int _hangarDrones = 0;
  int _hangarFlights = 0;
  int _hangarLogs = 0;
  double _hangarHours = 0;
  bool _loading = true;
  String? _uploading;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      final responses = await Future.wait([
        http.get(Uri.parse('$_api/api/profiles/$_uid')),
        http.get(Uri.parse('$_api/api/hangar'), headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        }),
      ]);
      final response = responses[0];
      if (response.statusCode != 200) throw Exception();
      final profile =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      Uint8List? avatar;
      Uint8List? cover;
      if ((profile['images'] as Map?)?['avatar'] != null) {
        final image = await http.get(
          Uri.parse('$_api/api/profiles/$_uid/images/avatar'),
        );
        if (image.statusCode == 200) avatar = image.bodyBytes;
      }
      if ((profile['images'] as Map?)?['cover'] != null) {
        final image = await http.get(
          Uri.parse('$_api/api/profiles/$_uid/images/cover'),
        );
        if (image.statusCode == 200) cover = image.bodyBytes;
      }
      final hangar = responses[1].statusCode == 200
          ? jsonDecode(responses[1].body) as Map<String, dynamic>
          : <String, dynamic>{};
      final aircraft = hangar['aircraft'] as List? ?? const [];
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _avatar = avatar;
        _cover = cover;
        _hangarDrones = aircraft.length;
        _hangarFlights = aircraft.fold<int>(
            0,
            (sum, item) =>
                sum + (((item as Map)['flights'] as num?)?.toInt() ?? 0));
        _hangarHours = aircraft.fold<double>(
            0,
            (sum, item) =>
                sum +
                (((item as Map)['flightHours'] as num?)?.toDouble() ?? 0));
        _hangarLogs = aircraft.fold<int>(
            0,
            (sum, item) =>
                sum + (((item as Map)['logs'] as List?)?.length ?? 0));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadImage(String type) async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null || _uid == null) return;
    setState(() => _uploading = type);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_api/api/profiles/$_uid/images/$type'),
      );
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        await file.readAsBytes(),
        filename: file.name,
      ));
      final response = await request.send();
      if (response.statusCode != 200) throw Exception();
      await _load();
      AppFeedback.success(type == 'cover'
          ? 'Portada actualizada.'
          : 'Foto profesional actualizada.');
    } catch (_) {
      AppFeedback.error('No fue posible cargar la fotografía.');
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _uploadDocument(String type) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx'],
    );
    if (file == null || _uid == null) return;
    setState(() => _uploading = type);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_api/api/profiles/$_uid/documents/$type'),
      );
      request.files.add(http.MultipartFile.fromBytes(
        'document',
        await file.readAsBytes(),
        filename: file.name,
      ));
      final response = await request.send();
      if (response.statusCode != 200) throw Exception();
      await _load();
      AppFeedback.success('Documento guardado correctamente.');
    } catch (_) {
      AppFeedback.error('No fue posible cargar el documento.');
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  String _joined(String key) {
    final values = (_profile[key] as List? ?? const []);
    return values.isEmpty ? 'Sin registrar' : values.join(', ');
  }

  Future<void> _openCareer() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CareerApplicationPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents = _profile['documents'] as Map<String, dynamic>?;
    final resumeReady = documents?['resume'] != null;
    final cipuReady = documents?['cipu'] != null;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: Colors.black,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 120),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
              child: Row(children: [
                IconButton.filledTonal(
                  onPressed: widget.onBack,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: .82),
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(PhosphorIconsRegular.caretLeft, size: 17),
                ),
                const SizedBox(width: 5),
                const Text('Tu perfil',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: _openCareer,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: .82),
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(PhosphorIconsRegular.gear, size: 17),
                ),
              ]),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(children: [
                _ProfileHero(
                  avatar: _avatar,
                  cover: _cover,
                  name: '${_profile['name'] ?? 'Piloto independiente'}',
                  email: FirebaseAuth.instance.currentUser?.email ?? '',
                  uploadingAvatar: _uploading == 'avatar',
                  uploadingCover: _uploading == 'cover',
                  verified: resumeReady && cipuReady,
                  onPhoto: () => _uploadImage('avatar'),
                  onCover: () => _uploadImage('cover'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
                  child: Row(children: [
                    _ProfileMetric(
                        value: _hangarHours.toStringAsFixed(1), label: 'Horas'),
                    _ProfileMetric(value: '$_hangarFlights', label: 'Vuelos'),
                    _ProfileMetric(
                      value: '$_hangarDrones',
                      label: 'Drones',
                    ),
                    _ProfileMetric(
                      value: '${(resumeReady ? 1 : 0) + (cipuReady ? 1 : 0)}/2',
                      label: 'Documentos',
                    ),
                  ]),
                ),
                Row(children: [
                  const Text('Tu actividad',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${_hangarFlights + _hangarLogs}',
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF777777))),
                  const SizedBox(width: 4),
                  const Icon(PhosphorIconsRegular.caretUp, size: 13),
                ]),
                const SizedBox(height: 9),
                _ActivityHeatmap(
                  flights: _hangarFlights,
                  logs: _hangarLogs,
                  hours: _hangarHours,
                ),
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AirspaceTheme.line),
                    ),
                    child: const Row(children: [
                      Icon(PhosphorIconsRegular.chartBar, size: 15),
                      SizedBox(width: 6),
                      Text('Actividad', style: TextStyle(fontSize: 10)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F5),
                      shape: BoxShape.circle,
                      border: Border.all(color: AirspaceTheme.line),
                    ),
                    child: const Icon(PhosphorIconsRegular.sparkle, size: 15),
                  ),
                  const Spacer(),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(PhosphorIconsRegular.pencilSimple,
                        color: Colors.white, size: 17),
                  ),
                ]),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AirspaceTheme.line),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: Colors.black,
                            backgroundImage:
                                _avatar == null ? null : MemoryImage(_avatar!),
                            child: _avatar == null
                                ? const Icon(PhosphorIconsRegular.user,
                                    color: Colors.white, size: 15)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Flexible(
                                      child: Text(
                                          '${_profile['name'] ?? 'Piloto independiente'}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(PhosphorIconsFill.sealCheck,
                                        size: 13, color: Color(0xFF35C99B)),
                                  ]),
                                  const Text('Hace 2 días',
                                      style: TextStyle(
                                          fontSize: 7,
                                          color: Color(0xFF929292))),
                                ]),
                          ),
                          const Icon(PhosphorIconsRegular.dotsThreeVertical,
                              size: 16),
                        ]),
                        const SizedBox(height: 9),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: AirspaceTheme.lime,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(PhosphorIconsRegular.mapPin, size: 11),
                                SizedBox(width: 4),
                                Text('Encuentra tu zona',
                                    style: TextStyle(fontSize: 7)),
                              ]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                            '${_profile['bio'] ?? 'Una vista que no se consigue desde tierra.'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 9, height: 1.3)),
                      ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            if (_showCareerFeatures)
              Container(
              padding: const EdgeInsets.fromLTRB(15, 15, 15, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AirspaceTheme.line),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: _openCareer,
                      borderRadius: BorderRadius.circular(16),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Icon(PhosphorIconsRegular.briefcase, size: 21),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Oportunidades profesionales',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                  SizedBox(height: 2),
                                  Text('Revisa o continúa tu postulación',
                                      style: TextStyle(
                                          fontSize: 8,
                                          color: Color(0xFF777777))),
                                ]),
                          ),
                          Icon(PhosphorIconsRegular.caretRight, size: 15),
                        ]),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1),
                    ),
                    const Text('Estado de verificación',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(
                        resumeReady && cipuReady
                            ? PhosphorIconsFill.sealCheck
                            : PhosphorIconsRegular.sealWarning,
                        color: resumeReady && cipuReady
                            ? const Color(0xFF139B72)
                            : const Color(0xFFE69A20),
                        size: 22,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          resumeReady && cipuReady
                              ? 'Documentación completa para revisión'
                              : 'Completa tus documentos profesionales',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ]),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1),
                    ),
                    const Text('Información del piloto',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    _Info('Ubicación',
                        '${_profile['location'] ?? 'Sin registrar'}'),
                    _Info('Horas declaradas',
                        '${_profile['flightHours'] ?? 0} h'),
                    _Info('Especialidades', _joined('specialties')),
                    _Info('Drones operados', _joined('drones')),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1),
                    ),
                    const Text('Documentos profesionales',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    _DocumentRow(
                      title: 'Hoja de vida',
                      ready: resumeReady,
                      busy: _uploading == 'resume',
                      onTap: () => _uploadDocument('resume'),
                    ),
                    const Divider(height: 1),
                    _DocumentRow(
                      title: 'Certificado CIPU',
                      ready: cipuReady,
                      busy: _uploading == 'cipu',
                      onTap: () => _uploadDocument('cipu'),
                    ),
                  ]),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                    child: CircularProgressIndicator(color: Colors.black)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.avatar,
    required this.cover,
    required this.name,
    required this.email,
    required this.uploadingAvatar,
    required this.uploadingCover,
    required this.verified,
    required this.onPhoto,
    required this.onCover,
  });
  final Uint8List? avatar;
  final Uint8List? cover;
  final String name;
  final String email;
  final bool uploadingAvatar;
  final bool uploadingCover;
  final bool verified;
  final VoidCallback onPhoto;
  final VoidCallback onCover;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 200,
        child: Stack(alignment: Alignment.topCenter, children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              onTap: uploadingCover ? null : onCover,
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFCFD6D6), Color(0xFF9FAEAF)],
                  ),
                  image: cover == null
                      ? null
                      : DecorationImage(
                          image: MemoryImage(cover!), fit: BoxFit.cover),
                ),
              ),
            ),
          ),
          Positioned(
            top: 92,
            left: 16,
            child: Stack(children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: AirspaceTheme.surface, shape: BoxShape.circle),
                child: CircleAvatar(
                  radius: 38,
                  backgroundColor: AirspaceTheme.ink,
                  backgroundImage: avatar == null ? null : MemoryImage(avatar!),
                  child: avatar == null
                      ? const Icon(PhosphorIconsRegular.user,
                          color: Colors.white, size: 28)
                      : null,
                ),
              ),
              Positioned(
                right: -2,
                bottom: 0,
                child: IconButton.filled(
                  onPressed: uploadingAvatar ? null : onPhoto,
                  style: IconButton.styleFrom(
                    backgroundColor: AirspaceTheme.lime,
                    foregroundColor: AirspaceTheme.ink,
                    side: const BorderSide(
                        color: AirspaceTheme.surface, width: 3),
                  ),
                  constraints:
                      const BoxConstraints.tightFor(width: 28, height: 28),
                  padding: EdgeInsets.zero,
                  icon: uploadingAvatar
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(PhosphorIconsRegular.pencilSimple, size: 13),
                ),
              ),
            ]),
          ),
          Positioned(
            top: 136,
            left: 102,
            right: 8,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600))),
                if (verified) ...[
                  const SizedBox(width: 6),
                  const Icon(PhosphorIconsFill.sealCheck,
                      size: 15, color: Color(0xFF20B98B)),
                ],
              ]),
              const SizedBox(height: 3),
              Text(email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 9, color: Color(0xFF777777))),
            ]),
          ),
        ]),
      );
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF75797C))),
        ]),
      );
}

class _ActivityHeatmap extends StatelessWidget {
  const _ActivityHeatmap({
    required this.flights,
    required this.logs,
    required this.hours,
  });
  final int flights;
  final int logs;
  final double hours;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final year = now.year;
    final activity = flights + logs;
    const weeks = 18;
    const dotGap = 4.0;
    final currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
    final calendarStart = currentWeekStart.subtract(
      const Duration(days: (weeks - 1) * 7),
    );

    int activityLevel(DateTime date) {
      if (date.year != year || date.isAfter(now) || activity <= 0) return 0;
      final seed = (date.month * 31 + date.day * 7 + activity * 3) % 17;
      final threshold = (1 + activity ~/ 5).clamp(1, 9);
      if (seed >= threshold) return 0;
      return 1 + ((seed + activity) % 3);
    }

    const activityColors = [
      Color(0xFF303431),
      Color(0xFF4F673E),
      Color(0xFF7DA950),
      AirspaceTheme.lime,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AirspaceTheme.darkGradient,
        borderRadius: BorderRadius.circular(23),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('$year',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('$activity registros',
              style: const TextStyle(color: Colors.white54, fontSize: 8)),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final dotSize =
                (constraints.maxWidth - (weeks - 1) * dotGap) / weeks;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(weeks, (week) {
                return Padding(
                  padding: EdgeInsets.only(
                    right: week == weeks - 1 ? 0 : dotGap,
                  ),
                  child: Column(
                    children: List.generate(7, (weekday) {
                      final date = calendarStart.add(
                        Duration(days: week * 7 + weekday),
                      );
                      final level = activityLevel(date);
                      final dateLabel =
                          '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: weekday == 6 ? 0 : dotGap,
                        ),
                        child: Tooltip(
                          message: level == 0
                              ? '$dateLabel · Sin actividad'
                              : '$dateLabel · Nivel $level de actividad',
                          triggerMode: TooltipTriggerMode.longPress,
                          child: Container(
                            width: dotSize,
                            height: dotSize,
                            decoration: BoxDecoration(
                              color: activityColors[level],
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            );
          },
        ),
        const SizedBox(height: 11),
        Row(children: [
          _ActivitySummary(value: '$flights', label: 'Vuelos'),
          _ActivitySummary(value: hours.toStringAsFixed(1), label: 'Horas'),
          _ActivitySummary(value: '$logs', label: 'Bitácoras'),
          const Spacer(),
          const Text('Menos',
              style: TextStyle(color: Colors.white38, fontSize: 7)),
          const SizedBox(width: 4),
          const _ActivityLegendDot(color: Color(0xFF303431)),
          const _ActivityLegendDot(color: Color(0xFF7DA950)),
          const _ActivityLegendDot(color: AirspaceTheme.lime),
        ]),
      ]),
    );
  }
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 7)),
        ]),
      );
}

class _ActivityLegendDot extends StatelessWidget {
  const _ActivityLegendDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 10))),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10, color: Color(0xFF666666))),
          ),
        ]),
      );
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.title,
    required this.ready,
    required this.busy,
    required this.onTap,
  });
  final String title;
  final bool ready;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -3),
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          ready
              ? PhosphorIconsFill.checkCircle
              : PhosphorIconsRegular.fileArrowUp,
          size: 19,
        ),
        title: Text(title, style: const TextStyle(fontSize: 10)),
        subtitle: Text(ready ? 'Documento cargado' : 'Pendiente',
            style: const TextStyle(fontSize: 8)),
        trailing: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black,
                  textStyle: const TextStyle(fontSize: 9),
                ),
                child: Text(ready ? 'Reemplazar' : 'Cargar'),
              ),
      );
}
