import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import 'airspace_theme.dart';
import 'app_feedback.dart';

const _careerApi = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://xpertcommunity-production.up.railway.app',
);

class CareerApplicationPage extends StatefulWidget {
  const CareerApplicationPage({super.key});

  @override
  State<CareerApplicationPage> createState() => _CareerApplicationPageState();
}

class _CareerApplicationPageState extends State<CareerApplicationPage> {
  List<Map<String, dynamic>> _roles = const [];
  Map<String, dynamic> _applications = {};
  Map<String, dynamic>? _application;
  String? _role;
  String? _uploading;
  bool _loading = true;
  bool _saving = false;
  bool _showRequirements = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _load() async {
    try {
      final response = await http.get(
        Uri.parse('$_careerApi/api/career/me'),
        headers: await _headers(),
      );
      if (response.statusCode != 200) throw Exception();
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      final applications = (body['applications'] as Map? ?? const {})
          .cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _roles = (body['roles'] as List? ?? const [])
            .map((item) => (item as Map).cast<String, dynamic>())
            .toList();
        _applications = applications;
        _application = null;
        _role = null;
        _showRequirements = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      AppFeedback.error('No pudimos cargar las oportunidades profesionales.');
    }
  }

  Map<String, dynamic>? get _selectedRole {
    for (final role in _roles) {
      if (role['id'] == _role) return role;
    }
    return null;
  }

  List<Map<String, dynamic>> get _requirements =>
      (_selectedRole?['requirements'] as List? ?? const [])
          .map((item) => (item as Map).cast<String, dynamic>())
          .toList();

  Map<String, dynamic> get _documents =>
      ((_application?['documents'] as Map?) ?? const {})
          .cast<String, dynamic>();

  int get _completed => _requirements
      .where((item) => _documents['${item['id']}'] != null)
      .length;

  double get _progress =>
      _requirements.isEmpty ? 0 : _completed / _requirements.length;

  bool get _submitted =>
      _application?['status'] == 'submitted' &&
      _requirements.isNotEmpty &&
      _completed == _requirements.length;

  Future<void> _selectRole(String role) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final response = await http.put(
        Uri.parse('$_careerApi/api/career/me'),
        headers: await _headers(),
        body: jsonEncode({'role': role}),
      );
      if (response.statusCode != 200) throw Exception();
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      if (!mounted) return;
      setState(() {
        _role = role;
        _application =
            (body['application'] as Map).cast<String, dynamic>();
        _applications = (body['applications'] as Map? ?? _applications)
            .cast<String, dynamic>();
        _showRequirements = true;
      });
    } catch (_) {
      AppFeedback.error('No fue posible seleccionar el cargo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadDocument(String requirementId) async {
    if (_uploading != null || _submitted) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (file == null) return;
    final size = await file.length();
    if (size != null && size > 10 * 1024 * 1024) {
      AppFeedback.error('El soporte no puede superar 10 MB.');
      return;
    }
    final bytes = await file.readAsBytes();
    setState(() => _uploading = requirementId);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '$_careerApi/api/career/me/$_role/requirements/$requirementId/document',
        ),
      );
      request.headers.addAll(await _headers(json: false));
      request.files.add(http.MultipartFile.fromBytes(
        'document',
        bytes,
        filename: file.name,
        contentType: _contentType(file.extension),
      ));
      final response = await http.Response.fromStream(await request.send());
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      if (response.statusCode != 200) {
        throw Exception(body['message'] ?? 'No se pudo cargar el soporte');
      }
      if (!mounted) return;
      setState(() {
        _application =
            (body['application'] as Map).cast<String, dynamic>();
        _applications = (body['applications'] as Map? ?? _applications)
            .cast<String, dynamic>();
      });
      AppFeedback.success('Soporte cargado correctamente.');
    } catch (_) {
      AppFeedback.error('No fue posible cargar el soporte.');
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  MediaType _contentType(String? extension) => switch (extension?.toLowerCase()) {
        'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
        'png' => MediaType('image', 'png'),
        _ => MediaType('application', 'pdf'),
      };

  Future<void> _submit() async {
    if (_completed != _requirements.length) {
      AppFeedback.show(
        'Adjunta un soporte para cada requisito antes de enviar tu perfil.',
        kind: FeedbackKind.warning,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final response = await http.post(
        Uri.parse('$_careerApi/api/career/me/$_role/submit'),
        headers: await _headers(),
      );
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
      if (response.statusCode != 200) {
        throw Exception(body['message'] ?? 'No se pudo enviar');
      }
      if (!mounted) return;
      setState(() {
        _application =
            (body['application'] as Map).cast<String, dynamic>();
        _applications = (body['applications'] as Map? ?? _applications)
            .cast<String, dynamic>();
      });
      AppFeedback.success('Tu perfil profesional fue enviado a revisión.');
    } catch (_) {
      AppFeedback.error('No fue posible enviar tu perfil profesional.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  IconData _roleIcon(String id) => switch (id) {
        'jefe_pilotos' => PhosphorIconsRegular.usersThree,
        'gerente_sms' => PhosphorIconsRegular.shieldCheck,
        _ => PhosphorIconsRegular.airplaneTilt,
      };

  void _back() {
    if (_showRequirements) {
      setState(() => _showRequirements = false);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AirspaceTheme.canvas,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.black))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
                  children: [
                    Row(children: [
                      IconButton.filledTonal(
                        onPressed: _back,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        icon: const Icon(PhosphorIconsRegular.caretLeft,
                            size: 17),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _showRequirements
                              ? 'Documentos del cargo'
                              : 'Oportunidades profesionales',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 18),
                    _heroCard(),
                    const SizedBox(height: 22),
                    if (_showRequirements)
                      _documentsView()
                    else
                      _roleSelector(),
                  ],
                ),
        ),
      );

  Widget _heroCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF202321), Color(0xFF101210)],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(PhosphorIconsRegular.briefcase,
              color: AirspaceTheme.lime, size: 28),
          const SizedBox(height: 15),
          const Text('Construye tu perfil profesional UAS',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 7),
          Text(
            _submitted
                ? 'Tus documentos están en proceso de verificación.'
                : 'Acredita tu experiencia y deja que las empresas encuentren tu perfil.',
            style: const TextStyle(
                color: Colors.white60, fontSize: 11, height: 1.4),
          ),
        ]),
      );

  Widget _roleSelector() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Selecciona el cargo que quieres ejercer',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          const Text(
            'Las empresas podrán encontrarte cuando tu perfil sea verificado.',
            style: TextStyle(fontSize: 10, color: Color(0xFF737873)),
          ),
          const SizedBox(height: 12),
          ..._roles.map((role) {
            final roleId = '${role['id']}';
            final application = _applications[roleId] as Map?;
            final documents = application?['documents'] as Map? ?? const {};
            final requirements = role['requirements'] as List? ?? const [];
            final total = requirements.length;
            final completed = requirements
                .where((item) => documents['${(item as Map)['id']}'] != null)
                .length;
            final submitted = application?['status'] == 'submitted' &&
                total > 0 &&
                completed == total;
            final selected = roleId == _role;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: _saving ? null : () => _selectRole(roleId),
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: selected ? AirspaceTheme.limeSoft : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: selected ? AirspaceTheme.lime : AirspaceTheme.line,
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: selected
                            ? AirspaceTheme.lime
                            : const Color(0xFFF0F1EF),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(_roleIcon('${role['id']}'), size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${role['title']}',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text('${role['subtitle']}',
                              style: const TextStyle(
                                  fontSize: 9, color: Color(0xFF737873))),
                          if (application != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              submitted
                                  ? 'Enviado a verificación'
                                  : '$completed de $total soportes cargados',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: submitted
                                    ? const Color(0xFF4E6811)
                                    : const Color(0xFF737873),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(PhosphorIconsRegular.caretRight, size: 17),
                  ]),
                ),
              ),
            );
          }),
        ],
      );

  Widget _documentsView() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AirspaceTheme.line),
            ),
            child: Row(children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: AirspaceTheme.lime,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(_roleIcon(_role ?? ''), size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_selectedRole?['title'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('${_selectedRole?['reference'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 9, color: Color(0xFF737873))),
                  ],
                ),
              ),
              if (!_submitted)
                TextButton(
                  onPressed: () => setState(() => _showRequirements = false),
                  child: const Text('Cambiar'),
                ),
            ]),
          ),
          const SizedBox(height: 18),
          Row(children: [
            const Text('Soportes requeridos',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('$_completed/${_requirements.length}',
                style: const TextStyle(fontSize: 11)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 7,
              backgroundColor: const Color(0xFFE1E4DF),
              color: AirspaceTheme.lime,
            ),
          ),
          const SizedBox(height: 6),
          const Text('Formatos permitidos: PDF, JPG o PNG · máximo 10 MB.',
              style: TextStyle(fontSize: 9, color: Color(0xFF737873))),
          const SizedBox(height: 12),
          ..._requirements.map(_requirementCard),
          const SizedBox(height: 8),
          if (_submitted)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AirspaceTheme.limeSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(children: [
                Icon(PhosphorIconsFill.sealCheck, size: 22),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Perfil enviado. Cuando sea verificado, las empresas podrán encontrarte y contactarte.',
                    style: TextStyle(fontSize: 10, height: 1.35),
                  ),
                ),
              ]),
            )
          else
            FilledButton.icon(
              onPressed: _saving || _uploading != null ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Icon(PhosphorIconsRegular.paperPlaneTilt, size: 18),
              label: Text(_saving ? 'Enviando…' : 'Enviar perfil a verificación'),
            ),
        ],
      );

  Widget _requirementCard(Map<String, dynamic> requirement) {
    final id = '${requirement['id']}';
    final document = _documents[id] as Map?;
    final ready = document != null;
    final busy = _uploading == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: ready ? const Color(0xFFB9D83A) : AirspaceTheme.line,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ready ? AirspaceTheme.limeSoft : const Color(0xFFF0F1EF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              ready
                  ? PhosphorIconsFill.checkCircle
                  : PhosphorIconsRegular.fileArrowUp,
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${requirement['title']}',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text('${requirement['detail']}',
                  style: const TextStyle(
                      fontSize: 9, color: Color(0xFF737873), height: 1.35)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        InkWell(
          onTap: _submitted || busy ? null : () => _uploadDocument(id),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: ready ? AirspaceTheme.limeSoft : const Color(0xFFF5F6F3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  ready
                      ? PhosphorIconsRegular.fileText
                      : PhosphorIconsRegular.uploadSimple,
                  size: 17,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  busy
                      ? 'Cargando soporte…'
                      : ready
                          ? '${document['name']}'
                          : 'Adjuntar soporte',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
              if (ready && !_submitted)
                const Text('Reemplazar', style: TextStyle(fontSize: 9)),
            ]),
          ),
        ),
      ]),
    );
  }
}
