import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_icons/phosphor_icons.dart';

import 'app_feedback.dart';

const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://xpertcommunity-production.up.railway.app',
);
const _developmentUserId = 'demo-pilot';

class PilotProfile {
  const PilotProfile({
    required this.name,
    required this.username,
    required this.bio,
    required this.location,
    required this.flightHours,
    required this.specialties,
    required this.drones,
    required this.followers,
    required this.following,
    this.resumeName,
    this.cipuName,
  });

  factory PilotProfile.fromJson(Map<String, dynamic> json) {
    final documents = json['documents'] as Map<String, dynamic>? ?? {};
    return PilotProfile(
      name: json['name'] as String? ?? 'Juan Serna',
      username: json['username'] as String? ?? 'juan.piloto',
      bio: json['bio'] as String? ?? 'Piloto UAS',
      location: json['location'] as String? ?? 'Colombia',
      flightHours: (json['flightHours'] as num?)?.toDouble() ?? 0,
      specialties: List<String>.from(json['specialties'] as List? ?? const []),
      drones: List<String>.from(json['drones'] as List? ?? const []),
      followers: (json['followers'] as num?)?.toInt() ?? 0,
      following: (json['following'] as num?)?.toInt() ?? 0,
      resumeName: (documents['resume'] as Map?)?['name'] as String?,
      cipuName: (documents['cipu'] as Map?)?['name'] as String?,
    );
  }

  static const fallback = PilotProfile(
    name: 'Juan Serna',
    username: 'juan.piloto',
    bio: 'Piloto UAS | Fotografía aérea y operaciones especializadas',
    location: 'Colombia',
    flightHours: 0,
    specialties: ['Fotografía aérea'],
    drones: [],
    followers: 0,
    following: 0,
  );

  final String name;
  final String username;
  final String bio;
  final String location;
  final double flightHours;
  final List<String> specialties;
  final List<String> drones;
  final int followers;
  final int following;
  final String? resumeName;
  final String? cipuName;

  Map<String, dynamic> toJson() => {
        'name': name,
        'username': username,
        'bio': bio,
        'location': location,
        'flightHours': flightHours,
        'specialties': specialties,
        'drones': drones,
      };
}

class _ProfileApi {
  Uri _uri(String path) => Uri.parse('$_apiBaseUrl$path');

  Future<PilotProfile> load() async {
    final response = await http
        .get(_uri('/api/profiles/$_developmentUserId'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw Exception('No se pudo cargar');
    return PilotProfile.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<PilotProfile> save(PilotProfile profile) async {
    final response = await http
        .put(
          _uri('/api/profiles/$_developmentUserId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(profile.toJson()),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('No se pudo guardar');
    return PilotProfile.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<String> upload(String type, PlatformFile file) async {
    final bytes = await file.readAsBytes();
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/profiles/$_developmentUserId/documents/$type'),
    );
    request.files.add(
      http.MultipartFile.fromBytes(
        'document',
        bytes,
        filename: file.name,
      ),
    );
    final response = await request.send().timeout(const Duration(seconds: 20));
    if (response.statusCode != 201) throw Exception('No se pudo subir el PDF');
    return file.name;
  }
}

class PilotProfilePage extends StatefulWidget {
  const PilotProfilePage({super.key});

  @override
  State<PilotProfilePage> createState() => _PilotProfilePageState();
}

class _PilotProfilePageState extends State<PilotProfilePage> {
  final _api = _ProfileApi();
  PilotProfile _profile = PilotProfile.fallback;
  bool _loading = true;
  bool _offline = false;
  String? _uploading;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await _api.load();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      if (mounted) setState(() => _offline = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final updated = await showModalBottomSheet<PilotProfile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(profile: _profile),
    );
    if (updated == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final saved = await _api.save(updated);
      if (mounted) setState(() => _profile = saved);
      _message('Perfil guardado correctamente');
    } catch (_) {
      _message('No fue posible guardar. Revisa la conexión con la API.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDocument(String type) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file == null || !mounted) return;
    final size = await file.length();
    if (size == null || size > 5 * 1024 * 1024) {
      _message('Selecciona un PDF de máximo 5 MB.');
      return;
    }
    setState(() => _uploading = type);
    try {
      await _api.upload(type, file);
      await _load();
      _message(type == 'cipu'
          ? 'Certificado CIPU guardado'
          : 'Hoja de vida guardada');
    } catch (_) {
      _message('No fue posible subir el documento.');
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  void _message(String text) {
    AppFeedback.info(text);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        color: Colors.black,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Perfil',
                            style: TextStyle(
                                fontSize: 25, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(
                            onPressed: () {},
                            icon:
                                const Icon(PhosphorIconsRegular.shareNetwork)),
                        IconButton(
                            onPressed: () {},
                            icon: const Icon(PhosphorIconsRegular.gearSix)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          width: 94,
                          height: 94,
                          decoration: const BoxDecoration(
                              color: Color(0xFF111111), shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Text(_initials,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const Spacer(),
                        _Count(
                            value:
                                '${_profile.flightHours.toStringAsFixed(_profile.flightHours % 1 == 0 ? 0 : 1)} h',
                            label: 'Vuelo'),
                        _Count(
                            value: '${_profile.followers}',
                            label: 'Seguidores'),
                        _Count(
                            value: '${_profile.following}', label: 'Siguiendo'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(_profile.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    Text('@${_profile.username}',
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF777777))),
                    const SizedBox(height: 9),
                    Text(_profile.bio,
                        style: const TextStyle(fontSize: 14, height: 1.35)),
                    const SizedBox(height: 7),
                    Row(children: [
                      const Icon(PhosphorIconsRegular.mapPin,
                          size: 16, color: Color(0xFF777777)),
                      const SizedBox(width: 4),
                      Text(_profile.location,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF777777))),
                    ]),
                    if (_offline) ...[
                      const SizedBox(height: 12),
                      const _StatusPill(
                          text: 'Esperando conexión con el servidor'),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton(
                        onPressed: _loading ? null : _edit,
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.black),
                        child: const Text('Editar perfil'),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text('Perfil profesional UAS',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _InfoCard(
                      icon: PhosphorIconsRegular.clockCounterClockwise,
                      title: 'Experiencia de vuelo',
                      value:
                          '${_profile.flightHours.toStringAsFixed(1)} horas registradas',
                    ),
                    _InfoCard(
                      icon: PhosphorIconsRegular.airplaneTilt,
                      title: 'Drones',
                      value: _profile.drones.isEmpty
                          ? 'Añade los equipos que operas'
                          : _profile.drones.join(' · '),
                    ),
                    _InfoCard(
                      icon: PhosphorIconsRegular.medal,
                      title: 'Especialidades',
                      value: _profile.specialties.isEmpty
                          ? 'Añade tus especialidades'
                          : _profile.specialties.join(' · '),
                    ),
                    const SizedBox(height: 18),
                    const Text('Documentos verificados',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _DocumentCard(
                      title: 'Hoja de vida',
                      fileName: _profile.resumeName,
                      loading: _uploading == 'resume',
                      onTap: () => _pickDocument('resume'),
                    ),
                    _DocumentCard(
                      title: 'Certificado CIPU',
                      fileName: _profile.cipuName,
                      loading: _uploading == 'cipu',
                      onTap: () => _pickDocument('cipu'),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _ProfileTab(label: 'Publicaciones', selected: true),
                        _ProfileTab(label: 'Respuestas'),
                        _ProfileTab(label: 'Multimedia'),
                      ],
                    ),
                    const SizedBox(height: 46),
                    const Center(
                        child: Text('Aún no hay publicaciones',
                            style: TextStyle(
                                color: Color(0xFF999999), fontSize: 15))),
                    const SizedBox(height: 130),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _initials {
    final parts = _profile.name.trim().split(RegExp(r'\s+'));
    return parts
        .take(2)
        .map((part) => part.isEmpty ? '' : part[0])
        .join()
        .toUpperCase();
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 72,
        child: Column(children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF777777))),
        ]),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(PhosphorIconsRegular.cloudSlash, size: 15),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 11)),
        ]),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: const Color(0xFFF6F6F6),
            borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(icon, size: 23),
          const SizedBox(width: 13),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(value,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6F6F6F))),
              ])),
        ]),
      );
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard(
      {required this.title,
      required this.fileName,
      required this.loading,
      required this.onTap});
  final String title;
  final String? fileName;
  final bool loading;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E5E5)),
              borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const Icon(PhosphorIconsRegular.filePdf, size: 27),
            const SizedBox(width: 13),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(fileName ?? 'Toca para adjuntar PDF',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF777777))),
                ])),
            if (loading)
              const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black))
            else
              Icon(
                  fileName == null
                      ? PhosphorIconsRegular.uploadSimple
                      : PhosphorIconsRegular.checkCircle,
                  size: 22),
          ]),
        ),
      );
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.label, this.selected = false});
  final String label;
  final bool selected;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.black : const Color(0xFF999999),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
      );
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.profile});
  final PilotProfile profile;
  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late final TextEditingController _location;
  late final TextEditingController _hours;
  late final TextEditingController _specialties;
  late final TextEditingController _drones;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _name = TextEditingController(text: profile.name);
    _username = TextEditingController(text: profile.username);
    _bio = TextEditingController(text: profile.bio);
    _location = TextEditingController(text: profile.location);
    _hours = TextEditingController(text: profile.flightHours.toString());
    _specialties = TextEditingController(text: profile.specialties.join(', '));
    _drones = TextEditingController(text: profile.drones.join(', '));
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _username,
      _bio,
      _location,
      _hours,
      _specialties,
      _drones
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _list(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  void _save() {
    Navigator.pop(
      context,
      PilotProfile(
        name: _name.text.trim(),
        username: _username.text.trim().replaceFirst('@', ''),
        bio: _bio.text.trim(),
        location: _location.text.trim(),
        flightHours: double.tryParse(_hours.text.replaceAll(',', '.')) ?? 0,
        specialties: _list(_specialties.text),
        drones: _list(_drones.text),
        followers: widget.profile.followers,
        following: widget.profile.following,
        resumeName: widget.profile.resumeName,
        cipuName: widget.profile.cipuName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        height: MediaQuery.sizeOf(context).height * .92,
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            title: const Text('Editar perfil',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(PhosphorIconsRegular.x)),
            actions: [
              TextButton(
                  onPressed: _save,
                  child: const Text('Guardar',
                      style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.w700)))
            ],
          ),
          body: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
            children: [
              _field(_name, 'Nombre completo'),
              _field(_username, 'Nombre de usuario'),
              _field(_bio, 'Descripción profesional', lines: 3),
              _field(_location, 'Ubicación'),
              _field(_hours, 'Horas de vuelo', number: true),
              _field(_specialties, 'Especialidades separadas por comas'),
              _field(_drones, 'Drones operados separados por comas'),
            ],
          ),
        ),
      );

  Widget _field(TextEditingController controller, String label,
          {int lines = 1, bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: TextField(
          controller: controller,
          maxLines: lines,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        ),
      );
}
