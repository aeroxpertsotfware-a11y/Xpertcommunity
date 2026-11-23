import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app_feedback.dart';
import 'airspace_theme.dart';

const _hangarApi = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://xpertcommunity-production.up.railway.app',
);

class DroneHangarPage extends StatefulWidget {
  const DroneHangarPage({super.key, required this.userId});

  final String userId;

  @override
  State<DroneHangarPage> createState() => _DroneHangarPageState();
}

class _DroneHangarPageState extends State<DroneHangarPage> {
  List<_Drone> _drones = const [];
  bool _loading = true;

  String get _storageKey => 'xpert_hangar_${widget.userId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    var cached = <_Drone>[];
    try {
      cached = raw == null
          ? <_Drone>[]
          : (jsonDecode(raw) as List)
              .map((item) =>
                  _Drone.fromJson((item as Map).cast<String, dynamic>()))
              .toList();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _drones = cached;
      _loading = false;
    });
    try {
      final response = await http.get(
        Uri.parse('$_hangarApi/api/hangar'),
        headers: await _authHeaders(),
      );
      if (response.statusCode != 200) throw Exception(_apiMessage(response));
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      var remote = (decoded['aircraft'] as List? ?? const [])
          .map((item) => _Drone.fromJson((item as Map).cast<String, dynamic>()))
          .toList();
      if (remote.isEmpty && cached.isNotEmpty) {
        final migrated = <_Drone>[];
        for (final drone in cached) {
          migrated.add(await _createRemote(drone));
        }
        remote = migrated;
      }
      if (!mounted) return;
      setState(() => _drones = remote);
      await _save();
    } catch (_) {
      // La copia local permite consultar el hangar sin conexión.
    }
  }

  Future<Map<String, String>> _authHeaders({bool json = false}) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) throw Exception('Debes iniciar sesión');
    return {
      'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  String _apiMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return '${body['message'] ?? 'No fue posible guardar los cambios'}';
    } catch (_) {
      return 'No fue posible guardar los cambios';
    }
  }

  Future<_Drone> _createRemote(_Drone drone) async {
    final response = await http.post(
      Uri.parse('$_hangarApi/api/hangar/drones'),
      headers: await _authHeaders(json: true),
      body: jsonEncode(drone.toJson()),
    );
    if (response.statusCode != 201) throw Exception(_apiMessage(response));
    return _Drone.fromJson(
      ((jsonDecode(response.body) as Map<String, dynamic>)['aircraft'] as Map)
          .cast<String, dynamic>(),
    );
  }

  Future<void> _updateRemote(_Drone drone) async {
    final response = await http.put(
      Uri.parse('$_hangarApi/api/hangar/drones/${drone.id}'),
      headers: await _authHeaders(json: true),
      body: jsonEncode(drone.toJson()),
    );
    if (response.statusCode != 200) throw Exception(_apiMessage(response));
  }

  Future<_FlightLog> _uploadLog(_Drone drone, PlatformFile file) async {
    final bytes = await file.readAsBytes();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_hangarApi/api/hangar/drones/${drone.id}/logs'),
    );
    request.headers.addAll(await _authHeaders());
    request.files.add(
      http.MultipartFile.fromBytes('log', bytes, filename: file.name),
    );
    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode != 201) throw Exception(_apiMessage(response));
    return _FlightLog.fromJson(
      ((jsonDecode(response.body) as Map<String, dynamic>)['log'] as Map)
          .cast<String, dynamic>(),
    );
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(_drones.map((drone) => drone.toJson()).toList()),
    );
  }

  Future<void> _addDrone() async {
    final drone = await showModalBottomSheet<_Drone>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => const _DroneFormSheet(),
    );
    if (drone == null || !mounted) return;
    try {
      final stored = await _createRemote(drone);
      if (!mounted) return;
      setState(() => _drones = [..._drones, stored]);
      await _save();
      AppFeedback.success('Dron agregado a Mi Hangar.');
    } catch (error) {
      AppFeedback.error(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openDrone(_Drone drone) async {
    final updated = await Navigator.of(context).push<_Drone>(
      MaterialPageRoute<_Drone>(
        builder: (_) => _DroneDetailPage(
          drone: drone,
          onUploadLog: (file) => _uploadLog(drone, file),
          onUpdate: _updateRemote,
        ),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      _drones = _drones
          .map((item) => item.id == updated.id ? updated : item)
          .toList();
    });
    await _save();
  }

  Future<void> _deleteDrone(_Drone drone) async {
    final confirmed =
        await AppFeedback.confirmDelete(context, itemName: 'este dron');
    if (!confirmed || !mounted) return;
    try {
      final response = await http.delete(
        Uri.parse('$_hangarApi/api/hangar/drones/${drone.id}'),
        headers: await _authHeaders(),
      );
      if (response.statusCode != 204) throw Exception(_apiMessage(response));
      if (!mounted) return;
      setState(() =>
          _drones = _drones.where((item) => item.id != drone.id).toList());
      await _save();
      AppFeedback.success('Dron eliminado de Mi Hangar.');
    } catch (error) {
      AppFeedback.error(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = _drones.isEmpty;
    final fleet = demo ? _demoFleet : _drones;
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Montserrat'),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F1),
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.black))
              : ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
                  children: [
                    Row(children: [
                      _FleetHeaderButton(
                        icon: PhosphorIconsRegular.caretLeft,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _addDrone,
                        icon: const Icon(PhosphorIconsRegular.plus, size: 15),
                        label: const Text('Agregar UAS'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 17, vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 18),
                    const Text('Flota UAS',
                        style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontSize: 34,
                            height: .98,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -1.6)),
                    const SizedBox(height: 8),
                    Text(
                      demo
                          ? 'Tus aeronaves aparecerán organizadas así'
                          : '${fleet.length} aeronave${fleet.length == 1 ? '' : 's'} registrada${fleet.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                          color: Color(0xFF888A8B), fontSize: 12),
                    ),
                    const SizedBox(height: 24),
                    ...List.generate(fleet.length, (index) {
                      final drone = fleet[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: _DroneCard(
                          drone: drone,
                          dark: index.isOdd,
                          demo: demo,
                          assetImage: index.isOdd
                              ? 'assets/images/drone_mavic_3.png'
                              : 'assets/dji consumer/drone_air_3s.png',
                          onTap: demo ? _addDrone : () => _openDrone(drone),
                          onDelete: demo ? null : () => _deleteDrone(drone),
                        ),
                      );
                    }),
                  ],
                ),
        ),
      ),
    );
  }
}

const _demoFleet = <_Drone>[
  _Drone(
      id: 'demo-air-3s',
      name: 'DJI AIR 3S',
      manufacturer: 'DJI',
      model: 'Air 3S · 45 min máx.',
      serialNumber: 'AIR3S-DEMO',
      status: 'Conectado',
      flightHours: 3.116,
      flights: 23,
      logs: []),
  _Drone(
      id: 'demo-mavic-3',
      name: 'DJI Mavic 3',
      manufacturer: 'DJI',
      model: 'Mavic 3 · 46 min máx.',
      serialNumber: 'MAVIC3-DEMO',
      status: 'Fuera de línea',
      flightHours: 1.783,
      flights: 12,
      logs: []),
];

class _FleetHeaderButton extends StatelessWidget {
  const _FleetHeaderButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
            child: Icon(icon, size: 20)),
      );
}

// ignore: unused_element
class _HangarSummary extends StatelessWidget {
  const _HangarSummary(
      {required this.drones, required this.flights, required this.hours});
  final int drones;
  final int flights;
  final double hours;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          gradient: AirspaceTheme.darkGradient,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF34363A)),
        ),
        child: Row(children: [
          _SummaryMetric(value: '$drones', label: 'Drones'),
          _SummaryMetric(value: '$flights', label: 'Vuelos'),
          _SummaryMetric(value: hours.toStringAsFixed(1), label: 'Horas'),
        ]),
      );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w400)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
      );
}

// ignore: unused_element
class _EmptyHangar extends StatelessWidget {
  const _EmptyHangar({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 80),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 78,
            height: 78,
            decoration: const BoxDecoration(
                color: AirspaceTheme.limeSoft, shape: BoxShape.circle),
            child: const Icon(PhosphorIconsRegular.airplaneTilt,
                size: 36, color: AirspaceTheme.ink),
          ),
          const SizedBox(height: 18),
          const Text('Tu hangar está vacío',
              style: TextStyle(fontSize: 19, color: AirspaceTheme.ink)),
          const SizedBox(height: 7),
          const Text(
            'Agrega tu primer dron para organizar vuelos, logs y mantenimiento.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, height: 1.35, color: AirspaceTheme.muted),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(PhosphorIconsRegular.plus),
            label: const Text('Agregar mi primer dron'),
            style: FilledButton.styleFrom(
              backgroundColor: AirspaceTheme.ink,
              minimumSize: const Size(230, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ]),
      );
}

class _DroneCard extends StatelessWidget {
  const _DroneCard(
      {required this.drone,
      required this.dark,
      required this.demo,
      required this.assetImage,
      required this.onTap,
      required this.onDelete});
  final _Drone drone;
  final bool dark;
  final bool demo;
  final String assetImage;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Material(
        color: dark ? const Color(0xFF171817) : Colors.white,
        elevation: dark ? 0 : 8,
        shadowColor: Colors.black.withValues(alpha: .06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(27),
          side: BorderSide(
              color: dark ? const Color(0xFF292B29) : const Color(0xFFE8E8E5)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(27),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(17, 15, 12, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(drone.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -.7)
                              .copyWith(
                                  color:
                                      dark ? Colors.white : AirspaceTheme.ink)),
                      const SizedBox(height: 3),
                      Text(drone.model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                                  fontFamily: 'Montserrat', fontSize: 9)
                              .copyWith(
                                  color: dark
                                      ? Colors.white60
                                      : AirspaceTheme.muted)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:
                        drone.status == 'Activo' || drone.status == 'Conectado'
                            ? AirspaceTheme.limeSoft
                            : dark
                                ? const Color(0xFF353735)
                                : const Color(0xFFE4E4E1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                      drone.status == 'Fuera de línea'
                          ? 'Offline'
                          : 'Conectado',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 10,
                        color: drone.status == 'Activo' ||
                                drone.status == 'Conectado'
                            ? AirspaceTheme.ink
                            : dark
                                ? Colors.white70
                                : const Color(0xFF666866),
                      )),
                ),
                if (onDelete != null)
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(PhosphorIconsRegular.dotsThree,
                        color: dark ? Colors.white70 : AirspaceTheme.ink),
                    onSelected: (value) {
                      if (value == 'delete') onDelete?.call();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Eliminar dron',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
              ]),
              const SizedBox(height: 14),
              _FleetCardImage(
                  drone: drone, assetImage: assetImage, height: 124),
              const SizedBox(height: 15),
              Row(children: [
                Expanded(
                  child: _DroneMetric(
                    icon: PhosphorIconsRegular.paperPlaneTilt,
                    value: '${drone.flights}',
                    label: 'Vuelos',
                  ),
                ),
                Expanded(
                  child: _DroneMetric(
                    icon: PhosphorIconsRegular.clock,
                    value: drone.flightHours.toStringAsFixed(1),
                    label: 'Horas',
                  ),
                ),
                Expanded(
                  child: _DroneMetric(
                    icon: PhosphorIconsRegular.fileText,
                    value: '${drone.logs.length}',
                    label: 'Bitácoras',
                  ),
                ),
              ]),
              const SizedBox(height: 15),
              Row(children: [
                Expanded(
                  child: Text(
                    drone.serialNumber.isEmpty
                        ? 'Serie sin registrar'
                        : 'S/N ${drone.serialNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, color: AirspaceTheme.muted),
                  ),
                ),
                const Text('Ver aeronave',
                    style: TextStyle(fontSize: 11, color: AirspaceTheme.ink)),
                const SizedBox(width: 5),
                const Icon(PhosphorIconsRegular.arrowRight,
                    size: 16, color: AirspaceTheme.ink),
              ]),
            ]),
          ),
        ),
      );
}

class _DroneMetric extends StatelessWidget {
  const _DroneMetric({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, size: 18, color: AirspaceTheme.ink),
        const SizedBox(height: 5),
        Text(value,
            style: const TextStyle(fontSize: 15, color: AirspaceTheme.ink)),
        Text(label,
            style: const TextStyle(fontSize: 9, color: AirspaceTheme.muted)),
      ]);
}

class _FleetCardImage extends StatelessWidget {
  const _FleetCardImage({
    required this.drone,
    required this.assetImage,
    required this.height,
  });

  final _Drone drone;
  final String assetImage;
  final double height;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      if (drone.imageBase64?.isNotEmpty == true) {
        bytes = base64Decode(drone.imageBase64!);
      }
    } catch (_) {}
    return SizedBox(
      width: double.infinity,
      height: height,
      child: bytes == null
          ? Image.asset(assetImage, fit: BoxFit.contain)
          : Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  Image.asset(assetImage, fit: BoxFit.contain),
            ),
    );
  }
}

class _DroneDetailPage extends StatefulWidget {
  const _DroneDetailPage({
    required this.drone,
    required this.onUploadLog,
    required this.onUpdate,
  });
  final _Drone drone;
  final Future<_FlightLog> Function(PlatformFile file) onUploadLog;
  final Future<void> Function(_Drone drone) onUpdate;

  @override
  State<_DroneDetailPage> createState() => _DroneDetailPageState();
}

class _DroneDetailPageState extends State<_DroneDetailPage> {
  late _Drone _drone;

  @override
  void initState() {
    super.initState();
    _drone = widget.drone;
  }

  Future<void> _pickPhoto() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final length = await file.length();
    if (length == null || length > 2 * 1024 * 1024) {
      AppFeedback.error('La imagen no puede superar 2 MB.');
      return;
    }
    final bytes = await file.readAsBytes();
    final updated = _drone.copyWith(imageBase64: base64Encode(bytes));
    try {
      await widget.onUpdate(updated);
      if (!mounted) return;
      setState(() => _drone = updated);
      AppFeedback.success('Fotografía actualizada.');
    } catch (error) {
      AppFeedback.error(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _addLog() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'csv', 'ulg', 'bin', 'log'],
    );
    if (file == null) return;
    try {
      final log = await widget.onUploadLog(file);
      if (!mounted) return;
      setState(() => _drone = _drone.copyWith(logs: [..._drone.logs, log]));
      AppFeedback.success('Bitácora guardada en tu cuenta.');
    } catch (error) {
      AppFeedback.error(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _finish() => Navigator.pop(context, _drone);

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _finish();
        },
        child: Scaffold(
          backgroundColor: AirspaceTheme.canvas,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: AirspaceTheme.ink,
            leading: IconButton(
              onPressed: _finish,
              icon: const Icon(PhosphorIconsRegular.caretLeft),
            ),
            title: Text(_drone.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
          ),
          body: ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
            children: [
              Stack(children: [
                _DroneImage(drone: _drone, width: double.infinity, height: 220),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: IconButton.filled(
                    onPressed: _pickPhoto,
                    style: IconButton.styleFrom(
                        backgroundColor: AirspaceTheme.lime,
                        foregroundColor: AirspaceTheme.ink),
                    icon: const Icon(PhosphorIconsRegular.camera),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _StatCard('${_drone.flights}', 'Vuelos')),
                const SizedBox(width: 9),
                Expanded(
                    child: _StatCard(
                        _drone.flightHours.toStringAsFixed(1), 'Horas')),
                const SizedBox(width: 9),
                Expanded(child: _StatCard('${_drone.logs.length}', 'Logs')),
              ]),
              const SizedBox(height: 22),
              const _DetailTitle('Información del dron'),
              _InfoRow('Fabricante', _drone.manufacturer),
              _InfoRow('Modelo', _drone.model),
              _InfoRow('Número de serie', _drone.serialNumber),
              _InfoRow('Estado', _drone.status),
              const SizedBox(height: 22),
              Row(children: [
                const Expanded(child: _DetailTitle('Logs de vuelo')),
                TextButton.icon(
                  onPressed: _addLog,
                  icon: const Icon(PhosphorIconsRegular.plus, size: 17),
                  label: const Text('Agregar'),
                ),
              ]),
              if (_drone.logs.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AirspaceTheme.ink,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('Aún no has agregado logs de vuelo.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9DA1A6))),
                )
              else
                ..._drone.logs.map((log) => _LogTile(log: log)),
              const SizedBox(height: 22),
              const _DetailTitle('Mantenimiento'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AirspaceTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AirspaceTheme.line),
                ),
                child: const Row(children: [
                  Icon(PhosphorIconsRegular.wrench,
                      size: 24, color: AirspaceTheme.ink),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Sin mantenimientos pendientes',
                        style:
                            TextStyle(fontSize: 13, color: AirspaceTheme.ink)),
                  ),
                ]),
              ),
            ],
          ),
        ),
      );
}

class _DroneImage extends StatelessWidget {
  const _DroneImage(
      {required this.drone, required this.width, required this.height});
  final _Drone drone;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    if (drone.imageBase64 != null) {
      try {
        bytes = base64Decode(drone.imageBase64!);
      } catch (_) {}
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: Container(
        width: width,
        height: height,
        decoration: const BoxDecoration(gradient: AirspaceTheme.skyGradient),
        child: bytes == null
            ? const Icon(PhosphorIconsRegular.airplaneTilt,
                size: 48, color: AirspaceTheme.ink)
            : Image.memory(bytes,
                fit: BoxFit.cover, filterQuality: FilterQuality.low),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            color: const Color(0xFF1A1B1E),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFF34363A))),
        child: Column(children: [
          Text(value,
              style: const TextStyle(fontSize: 17, color: Colors.white)),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF969A9E))),
        ]),
      );
}

class _DetailTitle extends StatelessWidget {
  const _DetailTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title,
            style: const TextStyle(fontSize: 17, color: AirspaceTheme.ink)),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 12, color: AirspaceTheme.ink))),
          Flexible(
            child: Text(value.isEmpty ? 'Sin registrar' : value,
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontSize: 12, color: AirspaceTheme.muted)),
          ),
        ]),
      );
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});
  final _FlightLog log;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: const Color(0xFF1A1B1E),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFF34363A))),
        child: Row(children: [
          const Icon(PhosphorIconsRegular.fileText,
              size: 23, color: AirspaceTheme.lime),
          const SizedBox(width: 11),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(log.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white)),
              Text('${(log.size / 1024).toStringAsFixed(1)} KB',
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xFF969A9E))),
            ]),
          ),
        ]),
      );
}

class _DroneFormSheet extends StatefulWidget {
  const _DroneFormSheet();
  @override
  State<_DroneFormSheet> createState() => _DroneFormSheetState();
}

class _DroneFormSheetState extends State<_DroneFormSheet> {
  final _name = TextEditingController();
  final _manufacturer = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _hours = TextEditingController();
  final _flights = TextEditingController();
  String _status = 'Activo';

  @override
  void dispose() {
    for (final controller in [
      _name,
      _manufacturer,
      _model,
      _serial,
      _hours,
      _flights
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      AppFeedback.error('Escribe un nombre para el dron.');
      return;
    }
    Navigator.pop(
      context,
      _Drone(
        id: const Uuid().v4(),
        name: _name.text.trim(),
        manufacturer: _manufacturer.text.trim(),
        model: _model.text.trim(),
        serialNumber: _serial.text.trim(),
        status: _status,
        flightHours: double.tryParse(_hours.text.replaceAll(',', '.')) ?? 0,
        flights: int.tryParse(_flights.text) ?? 0,
        logs: const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 10, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFD5D5D5),
                  borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(height: 18),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Agregar dron',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
            ),
            const SizedBox(height: 16),
            _field(_name, 'Nombre del dron *'),
            Row(children: [
              Expanded(child: _field(_manufacturer, 'Fabricante')),
              const SizedBox(width: 9),
              Expanded(child: _field(_model, 'Modelo')),
            ]),
            _field(_serial, 'Número de serie'),
            Row(children: [
              Expanded(child: _field(_hours, 'Horas de vuelo', numeric: true)),
              const SizedBox(width: 9),
              Expanded(child: _field(_flights, 'Vuelos', numeric: true)),
            ]),
            DropdownButtonFormField<String>(
              initialValue: _status,
              items: const ['Activo', 'Mantenimiento', 'Retirado']
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) => setState(() => _status = value ?? 'Activo'),
              decoration: const InputDecoration(labelText: 'Estado'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Guardar dron'),
              ),
            ),
          ]),
        ),
      );

  Widget _field(TextEditingController controller, String label,
          {bool numeric = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        ),
      );
}

class _Drone {
  const _Drone({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.model,
    required this.serialNumber,
    required this.status,
    required this.flightHours,
    required this.flights,
    required this.logs,
    this.imageBase64,
  });

  final String id;
  final String name;
  final String manufacturer;
  final String model;
  final String serialNumber;
  final String status;
  final double flightHours;
  final int flights;
  final List<_FlightLog> logs;
  final String? imageBase64;

  _Drone copyWith({String? imageBase64, List<_FlightLog>? logs}) => _Drone(
        id: id,
        name: name,
        manufacturer: manufacturer,
        model: model,
        serialNumber: serialNumber,
        status: status,
        flightHours: flightHours,
        flights: flights,
        logs: logs ?? this.logs,
        imageBase64: imageBase64 ?? this.imageBase64,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'manufacturer': manufacturer,
        'model': model,
        'serialNumber': serialNumber,
        'status': status,
        'flightHours': flightHours,
        'flights': flights,
        'logs': logs.map((log) => log.toJson()).toList(),
        'imageBase64': imageBase64,
      };

  factory _Drone.fromJson(Map<String, dynamic> json) => _Drone(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Mi dron'}',
        manufacturer: '${json['manufacturer'] ?? ''}',
        model: '${json['model'] ?? ''}',
        serialNumber: '${json['serialNumber'] ?? ''}',
        status: '${json['status'] ?? 'Activo'}',
        flightHours: (json['flightHours'] as num?)?.toDouble() ?? 0,
        flights: (json['flights'] as num?)?.toInt() ?? 0,
        logs: (json['logs'] as List? ?? const [])
            .map((item) =>
                _FlightLog.fromJson((item as Map).cast<String, dynamic>()))
            .toList(),
        imageBase64: json['imageBase64'] as String?,
      );
}

class _FlightLog {
  const _FlightLog(
      {required this.id,
      required this.name,
      required this.size,
      required this.addedAt});
  final String id;
  final String name;
  final int size;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'addedAt': addedAt.toIso8601String(),
      };

  factory _FlightLog.fromJson(Map<String, dynamic> json) => _FlightLog(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Log de vuelo'}',
        size: (json['size'] as num?)?.toInt() ?? 0,
        addedAt:
            DateTime.tryParse('${json['addedAt'] ?? ''}') ?? DateTime.now(),
      );
}
