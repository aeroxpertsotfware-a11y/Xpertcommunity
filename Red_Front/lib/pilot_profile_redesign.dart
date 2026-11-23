import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import 'app_feedback.dart';
import 'drone_hangar_page.dart';

const _api = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'https://xpertcommunity-production.up.railway.app');

class PilotProfileRedesignPage extends StatefulWidget {
  const PilotProfileRedesignPage({
    super.key,
    this.profileUserId,
    this.onCompose,
  });

  final String? profileUserId;
  final Future<bool> Function(String name, Uint8List? avatarBytes)? onCompose;

  @override
  State<PilotProfileRedesignPage> createState() =>
      _PilotProfileRedesignPageState();
}

class _PilotProfileRedesignPageState extends State<PilotProfileRedesignPage> {
  Map<String, dynamic> profile = {
    'name': 'Juan Camilo Serna',
    'username': 'juan.piloto',
    'bio': 'Piloto UAS | Fotografía aérea y operaciones especializadas',
    'location': 'Medellín, Antioquia, Colombia',
    'flightHours': 0,
    'followers': 0,
    'following': 0,
    'specialties': ['Fotografía aérea'],
    'drones': <String>[],
  };
  bool offline = false;
  String? uploading;
  int selectedTab = 0;
  String? userId;
  bool _isOwnProfile = true;
  Timer? _presenceRefresh;
  Uint8List? _avatarBytes;
  Uint8List? _coverBytes;
  String? _avatarCacheKey;
  String? _coverCacheKey;

  @override
  void initState() {
    super.initState();
    _initializeIdentity();
  }

  Future<void> _initializeIdentity() async {
    final authenticatedId = FirebaseAuth.instance.currentUser?.uid;
    final preferences = await SharedPreferences.getInstance();
    var storedId = widget.profileUserId ??
        authenticatedId ??
        preferences.getString('xpert_user_id');
    if (storedId == null || storedId.isEmpty) {
      storedId = const Uuid().v4();
      await preferences.setString('xpert_user_id', storedId);
    }
    if (!mounted) return;
    setState(() {
      userId = storedId;
      _isOwnProfile =
          widget.profileUserId == null || storedId == authenticatedId;
    });
    await _load();
    if (!mounted) return;
    _presenceRefresh = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _load(),
    );
  }

  @override
  void dispose() {
    _presenceRefresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final currentUserId = userId;
    if (currentUserId == null) return;
    try {
      final response = await http
          .get(Uri.parse('$_api/api/profiles/$currentUserId'))
          .timeout(const Duration(seconds: 7));
      if (response.statusCode == 200 && mounted) {
        final loadedProfile =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          profile = loadedProfile;
          offline = false;
        });
        unawaited(_cacheProfileImages(loadedProfile));
      }
    } catch (_) {
      if (mounted) setState(() => offline = true);
    }
  }

  Future<void> _edit() async {
    final currentUserId = userId;
    if (currentUserId == null) return;
    final name = TextEditingController(text: '${profile['name'] ?? ''}');
    final username =
        TextEditingController(text: '${profile['username'] ?? ''}');
    final bio = TextEditingController(text: '${profile['bio'] ?? ''}');
    final location =
        TextEditingController(text: '${profile['location'] ?? ''}');
    final hours = TextEditingController(text: '${profile['flightHours'] ?? 0}');
    final specialties = TextEditingController(
        text: List<String>.from(profile['specialties'] as List? ?? const [])
            .join(', '));
    final drones = TextEditingController(
        text: List<String>.from(profile['drones'] as List? ?? const [])
            .join(', '));
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.sizeOf(context).height * .82,
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(children: [
          Row(children: [
            const Text('Editar perfil',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(context, {
                ...profile,
                'name': name.text.trim(),
                'username': username.text.trim().replaceFirst('@', ''),
                'bio': bio.text.trim(),
                'location': location.text.trim(),
                'flightHours': double.tryParse(hours.text) ?? 0,
                'specialties': specialties.text
                    .split(',')
                    .map((value) => value.trim())
                    .where((value) => value.isNotEmpty)
                    .toList(),
                'drones': drones.text
                    .split(',')
                    .map((value) => value.trim())
                    .where((value) => value.isNotEmpty)
                    .toList(),
              }),
              child: const Text('Guardar',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w400)),
            ),
          ]),
          const SizedBox(height: 16),
          _field(name, 'Nombre completo'),
          _field(username, 'Nombre de usuario'),
          _field(bio, 'Descripción', lines: 3),
          _field(location, 'Ubicación'),
          _field(hours, 'Horas de vuelo', number: true),
          _field(specialties, 'Especialidades separadas por comas'),
          _field(drones, 'Drones operados separados por comas'),
        ]),
      ),
    );
    name.dispose();
    username.dispose();
    bio.dispose();
    location.dispose();
    hours.dispose();
    specialties.dispose();
    drones.dispose();
    if (result == null || !mounted) return;
    setState(() => profile = result);
    try {
      final response = await http
          .put(Uri.parse('$_api/api/profiles/$currentUserId'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(result))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw Exception();
      if (mounted) {
        setState(() => profile = jsonDecode(utf8.decode(response.bodyBytes)));
      }
      AppFeedback.success('Los cambios quedaron guardados.',
          title: 'Perfil actualizado');
    } catch (_) {
      AppFeedback.error('No fue posible guardar los cambios.',
          title: 'Error de conexión');
    }
  }

  Future<void> _upload(String type) async {
    final currentUserId = userId;
    if (currentUserId == null) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (file == null || !mounted) return;
    final length = await file.length();
    if (!mounted) return;
    if (length == null || length > 15 * 1024 * 1024) {
      AppFeedback.show('El PDF no puede superar 15 MB.',
          kind: FeedbackKind.warning);
      return;
    }
    setState(() => uploading = type);
    try {
      final request = http.MultipartRequest('POST',
          Uri.parse('$_api/api/profiles/$currentUserId/documents/$type'));
      request.files.add(http.MultipartFile.fromBytes(
          'document', await file.readAsBytes(),
          filename: file.name));
      final response =
          await request.send().timeout(const Duration(seconds: 60));
      if (response.statusCode != 201) throw Exception();
      await _load();
      AppFeedback.success('El documento quedó guardado.');
    } catch (_) {
      AppFeedback.error('No fue posible subir el documento.');
    } finally {
      if (mounted) setState(() => uploading = null);
    }
  }

  Future<void> _uploadImage(String type) async {
    final currentUserId = userId;
    if (currentUserId == null) return;
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null || !mounted) return;
    final length = await file.length();
    if (!mounted) return;
    if (length == null || length > 5 * 1024 * 1024) {
      AppFeedback.show('La imagen no puede superar 5 MB.',
          kind: FeedbackKind.warning);
      return;
    }
    setState(() => uploading = type);
    try {
      final extension = (file.extension ?? 'jpg').toLowerCase();
      final subtype = extension == 'jpg' ? 'jpeg' : extension;
      final request = http.MultipartRequest(
          'POST', Uri.parse('$_api/api/profiles/$currentUserId/images/$type'));
      request.files.add(http.MultipartFile.fromBytes(
          'image', await file.readAsBytes(),
          filename: file.name, contentType: MediaType('image', subtype)));
      final response =
          await request.send().timeout(const Duration(seconds: 25));
      if (response.statusCode != 201) throw Exception();
      await _load();
      AppFeedback.success(
          type == 'story' ? 'Historia guardada.' : 'Foto actualizada.');
    } catch (_) {
      AppFeedback.error('No fue posible guardar la imagen.');
    } finally {
      if (mounted) setState(() => uploading = null);
    }
  }

  Future<void> _uploadStory() async {
    final currentUserId = userId;
    if (currentUserId == null) return;
    final file = await FilePicker.pickFile(type: FileType.media);
    if (file == null || !mounted) return;
    final length = await file.length();
    if (!mounted) return;
    if (length == null || length > 50 * 1024 * 1024) {
      AppFeedback.show('La historia no puede superar 50 MB.',
          kind: FeedbackKind.warning);
      return;
    }
    final extension = (file.extension ?? '').toLowerCase();
    final mimeTypes = {
      'jpg': MediaType('image', 'jpeg'),
      'jpeg': MediaType('image', 'jpeg'),
      'png': MediaType('image', 'png'),
      'webp': MediaType('image', 'webp'),
      'mp4': MediaType('video', 'mp4'),
      'mov': MediaType('video', 'quicktime'),
    };
    final contentType = mimeTypes[extension];
    if (contentType == null) {
      AppFeedback.show('Selecciona una foto o video compatible.',
          kind: FeedbackKind.warning);
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final publish = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _StoryPreviewPage(
          bytes: bytes,
          filePath: file.path,
          mediaType: contentType.type,
        ),
      ),
    );
    if (publish != true || !mounted) return;
    setState(() => uploading = 'story');
    try {
      final request = http.MultipartRequest(
          'POST', Uri.parse('$_api/api/profiles/$currentUserId/story'));
      request.files.add(http.MultipartFile.fromBytes('story', bytes,
          filename: file.name, contentType: contentType));
      final response = await request.send().timeout(const Duration(minutes: 3));
      if (response.statusCode != 201) throw Exception();
      await _load();
      AppFeedback.success('Tu historia ya está publicada.');
    } catch (_) {
      AppFeedback.error('No fue posible publicar la historia.');
    } finally {
      if (mounted) setState(() => uploading = null);
    }
  }

  bool get _hasActiveStory {
    final story = profile['story'] as Map<String, dynamic>?;
    final expiresAt = DateTime.tryParse('${story?['expiresAt'] ?? ''}');
    return expiresAt != null &&
        expiresAt.toUtc().isAfter(DateTime.now().toUtc());
  }

  Future<void> _openStory() async {
    final ownerId = userId;
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final story = profile['story'] as Map<String, dynamic>?;
    if (ownerId == null || viewerId == null || story == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryViewerPage(
        ownerId: ownerId,
        viewerId: viewerId,
        ownerName: '${profile['name'] ?? ''}',
        mediaType: '${story['mediaType'] ?? 'image'}',
        isOwner: _isOwnProfile,
        initialViewCount: (story['viewCount'] as num?)?.toInt() ?? 0,
      ),
    ));
    await _load();
  }

  Future<void> _createPost() async {
    final currentUserId = userId;
    if (currentUserId == null) return;
    final controller = TextEditingController();
    final content = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('Nueva publicación', style: TextStyle(fontSize: 19)),
            const Spacer(),
            TextButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Publicar',
                    style: TextStyle(color: Colors.black))),
          ]),
          TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(hintText: '¿Qué estás pensando?'),
          ),
        ]),
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty || !mounted) return;
    try {
      final response = await http.post(
        Uri.parse('$_api/api/profiles/$currentUserId/posts'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': content}),
      );
      if (response.statusCode != 201) throw Exception();
      await _load();
      AppFeedback.success('Publicación guardada.');
    } catch (_) {
      AppFeedback.error('No fue posible publicar.');
    }
  }

  Future<void> _openComposer() async {
    final composer = widget.onCompose;
    if (composer == null) {
      await _createPost();
      return;
    }
    final published = await composer(
      '${profile['name'] ?? 'Usuario'}',
      _avatarBytes,
    );
    if (published) await _load();
  }

  Future<void> _likeProfilePost(String postId) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;
    await http.post(
      Uri.parse('$_api/api/profiles/posts/$postId/like'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': currentUserId}),
    );
    await _load();
  }

  Future<void> _commentProfilePost(String postId) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;
    final controller = TextEditingController();
    final content = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration:
                  const InputDecoration(hintText: 'Escribe un comentario'),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            icon: const Icon(PhosphorIconsRegular.paperPlaneTilt),
          ),
        ]),
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty) return;
    await http.post(
      Uri.parse('$_api/api/profiles/posts/$postId/comments'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': currentUserId, 'content': content}),
    );
    await _load();
  }

  Future<void> _repostProfilePost(String postId) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;
    await http.post(
      Uri.parse('$_api/api/profiles/posts/$postId/repost'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': currentUserId}),
    );
    await _load();
    AppFeedback.success('Publicación reposteada.');
  }

  Future<void> _deleteProfilePost(String postId) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || !_isOwnProfile) return;

    final confirmed = await AppFeedback.confirmDelete(
      context,
      itemName: 'esta publicación',
    );
    if (confirmed != true || !mounted) return;

    try {
      final response = await http.delete(
        Uri.parse('$_api/api/profiles/posts/$postId'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': currentUserId}),
      );
      if (response.statusCode != 204) throw Exception();
      if (!mounted) return;
      setState(() {
        final posts = (profile['posts'] as List? ?? const [])
            .where((post) => '${(post as Map)['id']}' != postId)
            .toList();
        profile = {...profile, 'posts': posts};
      });
      AppFeedback.success('Publicación eliminada.');
    } catch (_) {
      AppFeedback.error('No fue posible eliminar la publicación.');
    }
  }

  void _notice(String message) {
    AppFeedback.info(message);
  }

  void _options(String title, List<String> options) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
                alignment: Alignment.centerLeft,
                child: Text(title, style: const TextStyle(fontSize: 20))),
            const SizedBox(height: 12),
            ...options.map((option) => ListTile(
                  title: Text(option),
                  trailing: const Icon(PhosphorIconsRegular.caretRight),
                  onTap: () {
                    Navigator.pop(context);
                    _notice('$option: próximamente');
                  },
                )),
          ]),
        ),
      ),
    );
  }

  void _search() {
    showSearch<void>(context: context, delegate: _PilotSearchDelegate());
  }

  Future<void> _openHangar() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || !_isOwnProfile) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DroneHangarPage(userId: currentUserId),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
          {int lines = 1, bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          maxLines: lines,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        ),
      );

  String get initials => '${profile['name'] ?? 'P'}'
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((word) => word.isEmpty ? '' : word[0])
      .join()
      .toUpperCase();

  bool _hasImage(String type) =>
      (profile['images'] as Map<String, dynamic>?)?[type] != null;

  String _imageUrl(String type) {
    final metadata =
        (profile['images'] as Map<String, dynamic>?)?[type] as Map?;
    return '$_api/api/profiles/$userId/images/$type?v=${metadata?['uploadedAt'] ?? ''}';
  }

  Future<void> _cacheProfileImages(Map<String, dynamic> loadedProfile) async {
    final images = loadedProfile['images'] as Map<String, dynamic>?;
    await Future.wait([
      _cacheProfileImage('avatar', images?['avatar'] as Map<String, dynamic>?),
      _cacheProfileImage('cover', images?['cover'] as Map<String, dynamic>?),
    ]);
  }

  Future<void> _cacheProfileImage(
      String type, Map<String, dynamic>? metadata) async {
    if (metadata == null || userId == null) return;
    final key = '${metadata['uploadedAt'] ?? metadata['name'] ?? ''}';
    final currentKey = type == 'avatar' ? _avatarCacheKey : _coverCacheKey;
    final currentBytes = type == 'avatar' ? _avatarBytes : _coverBytes;
    if (key == currentKey && currentBytes != null) return;
    try {
      final response = await http
          .get(Uri.parse(_imageUrl(type)))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 || !mounted) return;
      setState(() {
        if (type == 'avatar') {
          _avatarBytes = response.bodyBytes;
          _avatarCacheKey = key;
        } else {
          _coverBytes = response.bodyBytes;
          _coverCacheKey = key;
        }
      });
    } catch (_) {
      // Conserva la última imagen disponible si la red tarda o se interrumpe.
    }
  }

  ImageProvider<Object>? _profileImage(String type) {
    final bytes = type == 'avatar' ? _avatarBytes : _coverBytes;
    if (bytes != null) return MemoryImage(bytes);
    return _hasImage(type) ? NetworkImage(_imageUrl(type)) : null;
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        color: Colors.black,
        child: CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(900),
          physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${profile['bio'] ?? ''}',
                            style: const TextStyle(fontSize: 13, height: 1.35)),
                        if (offline) ...[
                          const SizedBox(height: 9),
                          const Text('Esperando conexión con el servidor',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF777777))),
                        ],
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed:
                                  uploading == null ? _uploadStory : null,
                              icon: const Icon(PhosphorIconsRegular.plusCircle),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Agregar historia',
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.black,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(13)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _edit,
                              icon:
                                  const Icon(PhosphorIconsRegular.pencilSimple),
                              label: const Text('Editar perfil'),
                              style: FilledButton.styleFrom(
                                foregroundColor: Colors.black,
                                backgroundColor: const Color(0xFFE9EAEC),
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(13)),
                              ),
                            ),
                          ),
                        ]),
                        if (_isOwnProfile) ...[
                          const SizedBox(height: 14),
                          _hangarCard(),
                        ],
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _Tab('Todo', selectedTab == 0,
                                () => setState(() => selectedTab = 0)),
                            _Tab('Fotos', selectedTab == 1,
                                () => setState(() => selectedTab = 1)),
                            _Tab('Vuelos', selectedTab == 2,
                                () => setState(() => selectedTab = 2)),
                            _Tab('Certificados', selectedTab == 3,
                                () => setState(() => selectedTab = 3)),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Row(children: [
                          const Text('Información del piloto UAS',
                              style: TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w400)),
                          const Spacer(),
                          IconButton(
                              onPressed: _edit,
                              icon: const Icon(
                                  PhosphorIconsRegular.pencilSimple)),
                        ]),
                        _detail(PhosphorIconsRegular.mapPin, 'Ubicación',
                            '${profile['location'] ?? 'Sin ubicación'}'),
                        _detail(
                            PhosphorIconsRegular.clockCounterClockwise,
                            'Experiencia',
                            '${profile['flightHours'] ?? 0} horas de vuelo'),
                        _detail(
                            PhosphorIconsRegular.airplaneTilt,
                            'Drones operados',
                            _joined('drones', 'Añade los equipos que operas')),
                        _detail(PhosphorIconsRegular.medal, 'Especialidades',
                            _joined('specialties', 'Añade tus especialidades')),
                        const SizedBox(height: 22),
                        const Text('Documentos del piloto',
                            style: TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w400)),
                        const SizedBox(height: 12),
                        _document('Hoja de vida', 'resume'),
                        _document('Certificado CIPU', 'cipu'),
                        const SizedBox(height: 24),
                        Row(children: [
                          const Text('Todas las publicaciones',
                              style: TextStyle(
                                  fontSize: 19, fontWeight: FontWeight.w400)),
                          const Spacer(),
                          TextButton(
                              onPressed: () => _options('Filtros', [
                                    'Más recientes',
                                    'Más antiguas',
                                    'Con multimedia'
                                  ]),
                              child: const Text('Filtros',
                                  style: TextStyle(color: Color(0xFF777777)))),
                        ]),
                        const SizedBox(height: 18),
                        InkWell(
                            onTap: _openComposer,
                            child: Row(children: [
                              CircleAvatar(
                                  radius: 22,
                                  backgroundColor: Colors.black,
                                  child: Text(initials,
                                      style: const TextStyle(
                                          color: Colors.white))),
                              const SizedBox(width: 12),
                              const Expanded(
                                  child: Text('¿Qué estás pensando?',
                                      style: TextStyle(fontSize: 15))),
                              const Icon(PhosphorIconsRegular.image, size: 24),
                            ])),
                        const SizedBox(height: 44),
                        if ((profile['posts'] as List? ?? const []).isEmpty)
                          const Center(
                              child: Text('Aún no hay publicaciones',
                                  style: TextStyle(color: Color(0xFF999999))))
                        else
                          ...(profile['posts'] as List).map((post) =>
                              _profilePostCard(
                                  (post as Map).cast<String, dynamic>())),
                        const SizedBox(height: 130),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _profilePostCard(Map<String, dynamic> post) {
    final imageCacheWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(480, 1440);
    final postId = '${post['id'] ?? ''}';
    final imageUrl = post['hasImage'] == true
        ? '$_api/api/profiles/posts/$postId/media'
        : null;
    final createdAt =
        DateTime.tryParse('${post['createdAt'] ?? ''}')?.toLocal();
    final elapsed =
        createdAt == null ? null : DateTime.now().difference(createdAt);
    final time = elapsed == null || elapsed.inMinutes < 1
        ? 'ahora'
        : elapsed.inMinutes < 60
            ? '${elapsed.inMinutes} min'
            : elapsed.inHours < 24
                ? '${elapsed.inHours} h'
                : '${elapsed.inDays} d';
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE9E9E9)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.black,
            backgroundImage:
                _avatarBytes == null ? null : MemoryImage(_avatarBytes!),
            child: _avatarBytes == null
                ? Text(initials,
                    style: const TextStyle(color: Colors.white, fontSize: 12))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${profile['name'] ?? ''}  $time',
                style: const TextStyle(fontSize: 13)),
          ),
          if (_isOwnProfile)
            PopupMenuButton<String>(
              tooltip: 'Opciones de la publicación',
              icon: const Icon(PhosphorIconsRegular.dotsThree),
              onSelected: (value) {
                if (value == 'delete') _deleteProfilePost(postId);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(PhosphorIconsRegular.trash, color: Colors.red),
                    SizedBox(width: 10),
                    Text('Eliminar publicación',
                        style: TextStyle(color: Colors.red)),
                  ]),
                ),
              ],
            )
          else
            const Icon(PhosphorIconsRegular.dotsThree),
        ]),
        if ('${post['content'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('${post['content']}',
              style: const TextStyle(fontSize: 14, height: 1.35)),
        ],
        if (imageUrl != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                imageUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                cacheWidth: imageCacheWidth,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const ColoredBox(color: Color(0xFFF3F3F3)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 13),
        Row(children: [
          _profilePostAction(
            post['liked'] == true
                ? PhosphorIconsFill.heart
                : PhosphorIconsRegular.heart,
            '${post['likes'] ?? 0}',
            () => _likeProfilePost(postId),
          ),
          _profilePostAction(PhosphorIconsRegular.chatCircle,
              '${post['comments'] ?? 0}', () => _commentProfilePost(postId)),
          _profilePostAction(PhosphorIconsRegular.repeat,
              '${post['reposts'] ?? 0}', () => _repostProfilePost(postId)),
          _profilePostAction(PhosphorIconsRegular.paperPlaneTilt, '', () {}),
        ]),
      ]),
    );
  }

  Widget _profilePostAction(
          IconData icon, String label, VoidCallback onPressed) =>
      Expanded(
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 21),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 11)),
              ],
            ]),
          ),
        ),
      );

  Widget _header() => SizedBox(
        height: 350,
        child: Stack(children: [
          GestureDetector(
              onTap: () => _uploadImage('cover'),
              child: Container(
                height: 205,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF525458), Color(0xFFC9CACE)],
                  ),
                  image: _hasImage('cover')
                      ? DecorationImage(
                          image: _profileImage('cover')!, fit: BoxFit.cover)
                      : null,
                ),
              )),
          Positioned(
            top: 38,
            left: 10,
            right: 10,
            child: Row(children: [
              const Spacer(),
              IconButton(
                  onPressed: _edit,
                  icon: const Icon(PhosphorIconsRegular.pencilSimple,
                      color: Colors.white, size: 26)),
              IconButton(
                  onPressed: _search,
                  icon: const Icon(PhosphorIconsRegular.magnifyingGlass,
                      color: Colors.white, size: 26)),
              IconButton(
                  onPressed: () => _options('Opciones del perfil',
                      ['Compartir perfil', 'Configuración', 'Privacidad']),
                  icon: const Icon(PhosphorIconsRegular.dotsThreeCircle,
                      color: Colors.white, size: 28)),
            ]),
          ),
          Positioned(
              top: 142,
              right: 22,
              child: IconButton(
                  onPressed: () => _uploadImage('cover'),
                  icon: const Icon(PhosphorIconsRegular.camera,
                      color: Colors.white, size: 28))),
          Positioned(
            top: 178,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(32))),
            ),
          ),
          Positioned(
            top: 130,
            left: 22,
            child: GestureDetector(
                onTap: _hasActiveStory
                    ? _openStory
                    : (_isOwnProfile ? () => _uploadImage('avatar') : null),
                child: CircleAvatar(
                  radius: 62,
                  backgroundColor:
                      _hasActiveStory ? const Color(0xFF1473E6) : Colors.white,
                  child: CircleAvatar(
                    radius: 57,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 53,
                      backgroundColor: Colors.black,
                      backgroundImage: _profileImage('avatar'),
                      child: _hasImage('avatar')
                          ? null
                          : Text(initials,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w400)),
                    ),
                  ),
                )),
          ),
          if (_isOwnProfile)
            Positioned(
              top: 210,
              left: 111,
              child: GestureDetector(
                  onTap: () => _uploadImage('avatar'),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                        color: Color(0xFFE9EAEC), shape: BoxShape.circle),
                    child: const Icon(PhosphorIconsFill.camera, size: 18),
                  )),
            ),
          if (!_isOwnProfile && _isProfileOnline)
            Positioned(
              top: 207,
              left: 110,
              child: Container(
                width: 29,
                height: 29,
                decoration: BoxDecoration(
                  color: const Color(0xFF22A45D),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          Positioned(
            top: 211,
            left: 156,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${profile['name']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w400)),
                Text('@${profile['username']}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF777777))),
                if (!_isOwnProfile) ...[
                  const SizedBox(height: 5),
                  _presenceStatus(),
                ],
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Metric('${profile['followers'] ?? 0}', 'Seguidores'),
                _Metric('${profile['following'] ?? 0}', 'Siguiendo'),
                _Metric('${profile['flightHours'] ?? 0}', 'Horas de vuelo'),
                const _Metric('0', 'Publicaciones'),
              ],
            ),
          ),
        ]),
      );

  bool get _isProfileOnline {
    final presence = profile['presence'] as Map<String, dynamic>?;
    final rawLastSeen = presence?['lastSeen']?.toString();
    final lastSeen =
        rawLastSeen == null ? null : DateTime.tryParse(rawLastSeen);
    final elapsed = lastSeen == null
        ? null
        : DateTime.now().toUtc().difference(lastSeen.toUtc());
    return presence?['isOnline'] == true &&
        elapsed != null &&
        elapsed < const Duration(seconds: 90);
  }

  Widget _presenceStatus() {
    final presence = profile['presence'] as Map<String, dynamic>?;
    final rawLastSeen = presence?['lastSeen']?.toString();
    final lastSeen =
        rawLastSeen == null ? null : DateTime.tryParse(rawLastSeen);
    final elapsed = lastSeen == null
        ? null
        : DateTime.now().toUtc().difference(lastSeen.toUtc());
    final isOnline = _isProfileOnline;

    String label;
    if (isOnline) {
      label = 'En línea';
    } else if (elapsed == null) {
      label = 'Sin actividad reciente';
    } else if (elapsed.inMinutes < 1) {
      label = 'Se desconectó hace unos segundos';
    } else if (elapsed.inMinutes < 60) {
      label = 'Se desconectó hace ${elapsed.inMinutes} min';
    } else if (elapsed.inHours < 24) {
      label = 'Se desconectó hace ${elapsed.inHours} h';
    } else {
      label = 'Se desconectó hace ${elapsed.inDays} d';
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: isOnline ? const Color(0xFF22A45D) : const Color(0xFFAAAAAA),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: Color(0xFF777777)),
        ),
      ),
    ]);
  }

  String _joined(String key, String empty) {
    final values = List<String>.from(profile[key] as List? ?? const []);
    return values.isEmpty ? empty : values.join(' · ');
  }

  Widget _hangarCard() => InkWell(
        onTap: _openHangar,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7E7E7)),
          ),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(PhosphorIconsRegular.airplaneTilt,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mi Hangar',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    SizedBox(height: 3),
                    Text('Drones, vuelos, logs y mantenimiento',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF686868))),
                  ]),
            ),
            const Icon(PhosphorIconsRegular.caretRight, size: 21),
          ]),
        ),
      );

  Widget _detail(IconData icon, String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, size: 25),
          const SizedBox(width: 15),
          Expanded(
              child: Text.rich(TextSpan(children: [
            TextSpan(
                text: '$title\n',
                style: const TextStyle(fontWeight: FontWeight.w400)),
            TextSpan(
                text: value,
                style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
          ]))),
        ]),
      );

  Widget _document(String title, String type) {
    final documents = profile['documents'] as Map<String, dynamic>? ?? {};
    final data = documents[type] as Map<String, dynamic>?;
    return InkWell(
      onTap: uploading == null ? () => _upload(type) : null,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E5E5)),
            borderRadius: BorderRadius.circular(17)),
        child: Row(children: [
          const Icon(PhosphorIconsRegular.filePdf, size: 25),
          const SizedBox(width: 13),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w400)),
                Text(data?['name'] as String? ?? 'Sin documento adjunto',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF777777))),
              ])),
          if (uploading == type)
            const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black))
          else
            Icon(data == null
                ? PhosphorIconsRegular.uploadSimple
                : PhosphorIconsRegular.checkCircle),
        ]),
      ),
    );
  }
}

class _StoryPreviewPage extends StatefulWidget {
  const _StoryPreviewPage({
    required this.bytes,
    required this.filePath,
    required this.mediaType,
  });

  final Uint8List bytes;
  final String? filePath;
  final String mediaType;

  @override
  State<_StoryPreviewPage> createState() => _StoryPreviewPageState();
}

class _StoryPreviewPageState extends State<_StoryPreviewPage> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    final path = widget.filePath;
    if (widget.mediaType == 'video' && path != null) {
      final controller = VideoPlayerController.file(File(path));
      _videoController = controller;
      controller.initialize().then((_) {
        if (!mounted) return;
        controller
          ..setLooping(true)
          ..play();
        setState(() {});
      });
    }
  }

  Future<void> _askToClose() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFF2F2F2),
        title: const Text('¿Descartar historia?',
            style: TextStyle(fontWeight: FontWeight.w400)),
        content: const Text(
          'La foto o el video seleccionado no se publicará.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child:
                const Text('Continuar', style: TextStyle(color: Colors.black)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.black),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context, false);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _askToClose();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(children: [
              Positioned.fill(
                child: widget.mediaType == 'image'
                    ? Image.memory(widget.bytes, fit: BoxFit.contain)
                    : _videoController?.value.isInitialized == true
                        ? Center(
                            child: AspectRatio(
                              aspectRatio: _videoController!.value.aspectRatio,
                              child: VideoPlayer(_videoController!),
                            ),
                          )
                        : const Center(
                            child:
                                CircularProgressIndicator(color: Colors.white)),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  onPressed: _askToClose,
                  icon: const Icon(PhosphorIconsRegular.x,
                      color: Colors.white, size: 29),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(PhosphorIconsRegular.paperPlaneTilt),
                  label: const Text('Publicar historia'),
                  style: FilledButton.styleFrom(
                    foregroundColor: Colors.black,
                    backgroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

class StoryViewerPage extends StatefulWidget {
  const StoryViewerPage({
    super.key,
    required this.ownerId,
    required this.viewerId,
    required this.ownerName,
    required this.mediaType,
    required this.isOwner,
    required this.initialViewCount,
  });

  final String ownerId;
  final String viewerId;
  final String ownerName;
  final String mediaType;
  final bool isOwner;
  final int initialViewCount;

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoController;
  late final AnimationController _progressController;
  late int _viewCount;

  String get _mediaUrl => '$_api/api/profiles/${widget.ownerId}/story/media';

  @override
  void initState() {
    super.initState();
    _viewCount = widget.initialViewCount;
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          Navigator.maybePop(context);
        }
      });
    _registerView();
    if (widget.mediaType == 'video') {
      final controller = VideoPlayerController.networkUrl(Uri.parse(_mediaUrl));
      _videoController = controller;
      controller.initialize().then((_) {
        if (!mounted) return;
        controller
          ..setLooping(false)
          ..play();
        _progressController.duration = controller.value.duration;
        _progressController.forward(from: 0);
        setState(() {});
      });
    } else {
      _progressController.forward();
    }
  }

  Future<void> _registerView() async {
    try {
      final response = await http.post(
        Uri.parse('$_api/api/profiles/${widget.ownerId}/story/view'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'viewerId': widget.viewerId}),
      );
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() => _viewCount = (data['viewCount'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {}
  }

  Future<void> _react(String emoji) async {
    try {
      final response = await http.post(
        Uri.parse('$_api/api/profiles/${widget.ownerId}/story/reaction'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'viewerId': widget.viewerId, 'emoji': emoji}),
      );
      if (response.statusCode != 200) throw Exception();
      AppFeedback.success('Reacción enviada.');
    } catch (_) {
      AppFeedback.error('No fue posible enviar la reacción.');
    }
  }

  Future<void> _deleteStory() async {
    _progressController.stop();
    _videoController?.pause();
    final confirmed = await AppFeedback.confirmDelete(
      context,
      itemName: 'la historia',
    );
    if (!confirmed) {
      _videoController?.play();
      _progressController.forward();
      return;
    }
    try {
      final response = await http.delete(
        Uri.parse('$_api/api/profiles/${widget.ownerId}/story'),
      );
      if (response.statusCode != 204) throw Exception();
      AppFeedback.success('Historia eliminada.');
      if (mounted) Navigator.pop(context);
    } catch (_) {
      AppFeedback.error('No fue posible eliminar la historia.');
      _videoController?.play();
      _progressController.forward();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _videoController;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: widget.mediaType == 'video'
                ? video?.value.isInitialized == true
                    ? Center(
                        child: AspectRatio(
                          aspectRatio: video!.value.aspectRatio,
                          child: VideoPlayer(video),
                        ),
                      )
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white))
                : InteractiveViewer(
                    child: Center(
                      child: Image.network(
                        _mediaUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                                ? child
                                : const CircularProgressIndicator(
                                    color: Colors.white),
                      ),
                    ),
                  ),
          ),
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: Column(children: [
              AnimatedBuilder(
                animation: _progressController,
                builder: (context, child) => ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _progressController.value,
                    minHeight: 3,
                    backgroundColor: const Color(0x66FFFFFF),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xFF555555),
                  child: Icon(PhosphorIconsFill.user,
                      color: Colors.white, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.ownerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                ),
                if (widget.isOwner)
                  IconButton(
                    tooltip: 'Eliminar historia',
                    onPressed: _deleteStory,
                    icon: const Icon(PhosphorIconsRegular.trash,
                        color: Colors.white, size: 24),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(PhosphorIconsRegular.x,
                      color: Colors.white, size: 29),
                ),
              ]),
            ]),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: widget.isOwner
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(PhosphorIconsRegular.eye,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text('$_viewCount visualizaciones',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13)),
                  ])
                : Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0x99000000),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: ['❤️', '👍', '😍', '😂', '😮']
                          .map((emoji) => InkWell(
                                onTap: () => _react(emoji),
                                borderRadius: BorderRadius.circular(24),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(emoji,
                                      style: const TextStyle(fontSize: 25)),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 82,
        child: Column(children: [
          Text(value,
              maxLines: 1,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w400)),
          Text(label,
              maxLines: 1,
              style: const TextStyle(fontSize: 10, color: Color(0xFF777777))),
        ]),
      );
}

class _Tab extends StatelessWidget {
  const _Tab(this.label, this.selected, this.onTap);
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : Colors.black,
                fontWeight: FontWeight.w400)),
      ));
}

class _PilotSearchDelegate extends SearchDelegate<void> {
  @override
  String get searchFieldLabel => 'Buscar pilotos o publicaciones';

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              onPressed: () => query = '',
              icon: const Icon(PhosphorIconsRegular.x)),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        onPressed: () => close(context, null),
        icon: const Icon(PhosphorIconsRegular.arrowLeft),
      );

  @override
  Widget buildResults(BuildContext context) => _result();

  @override
  Widget buildSuggestions(BuildContext context) => _result();

  Widget _result() => Center(
        child: Text(query.isEmpty ? 'Escribe para buscar' : 'Buscando “$query”',
            style: const TextStyle(color: Color(0xFF777777))),
      );
}
