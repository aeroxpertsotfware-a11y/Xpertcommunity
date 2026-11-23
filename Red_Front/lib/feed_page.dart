import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import 'pilot_profile_redesign.dart';
import 'app_feedback.dart';
import 'notifications_page.dart';
import 'messages_page.dart';

const _api = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'https://xpertcommunity-production.up.railway.app');

const _demoStories = <Map<String, dynamic>>[
  {
    '_demo': true,
    'userId': 'demo-story-skycam',
    'name': 'SkyCam Colombia',
    'username': 'skycam.co',
    'color': 0xFF315B72,
    'caption': 'Amanecer sobre el Valle del Cocora',
    'story': {'mediaType': 'demo'},
  },
  {
    '_demo': true,
    'userId': 'demo-story-fpv',
    'name': 'Luis FPV',
    'username': 'luism.fpv',
    'color': 0xFF713F56,
    'caption': 'Probando una nueva ruta FPV',
    'story': {'mediaType': 'demo'},
  },
  {
    '_demo': true,
    'userId': 'demo-story-uas',
    'name': 'Ana UAS',
    'username': 'ana.uas',
    'color': 0xFF526B42,
    'caption': 'Lista de verificación antes del vuelo',
    'story': {'mediaType': 'demo'},
  },
];

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final Set<int> _likedDemoPosts = {};
  Timer? _presenceTimer;
  List<Map<String, dynamic>> _activeStories = const [];
  List<Map<String, dynamic>> _feedPosts = const [];
  final Set<String> _pendingPostActions = {};
  Map<String, dynamic>? _currentProfile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPresence();
    unawaited(_loadStories());
    unawaited(_loadFeedPosts());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    unawaited(_updatePresence(false));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPresence();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _presenceTimer?.cancel();
      unawaited(_updatePresence(false));
    }
  }

  void _startPresence() {
    _presenceTimer?.cancel();
    unawaited(_updatePresence(true));
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_updatePresence(true)),
    );
  }

  Future<void> _updatePresence(bool isOnline) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    try {
      await http
          .post(
            Uri.parse('$_api/api/profiles/$userId/presence'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'isOnline': isOnline}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // El vencimiento del latido marca al usuario como desconectado.
    }
  }

  Future<void> _loadStories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('$_api/api/profiles/stories/active')),
        http.get(Uri.parse('$_api/api/profiles/${user.uid}')),
      ]).timeout(const Duration(seconds: 8));
      if (!mounted || responses.any((response) => response.statusCode != 200)) {
        return;
      }
      final stories = (jsonDecode(utf8.decode(responses[0].bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
      final current = jsonDecode(utf8.decode(responses[1].bodyBytes))
          as Map<String, dynamic>;
      setState(() {
        _activeStories = stories;
        _currentProfile = current;
      });
    } catch (_) {}
  }

  Future<void> _openFeedStory(Map<String, dynamic> item) async {
    if (item['_demo'] == true) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _DemoStoryPage(story: item),
      ));
      return;
    }
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    final ownerId = '${item['userId'] ?? ''}';
    final story = item['story'] as Map<String, dynamic>?;
    if (viewerId == null || ownerId.isEmpty || story == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryViewerPage(
        ownerId: ownerId,
        viewerId: viewerId,
        ownerName: '${item['name'] ?? item['username'] ?? ''}',
        mediaType: '${story['mediaType'] ?? 'image'}',
        isOwner: ownerId == viewerId,
        initialViewCount: (story['viewCount'] as num?)?.toInt() ?? 0,
      ),
    ));
    await _loadStories();
  }

  Future<void> _loadFeedPosts() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    try {
      final response = await http
          .get(Uri.parse('$_api/api/profiles/posts/feed?viewerId=$userId'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || !mounted) return;
      setState(() {
        _feedPosts = (jsonDecode(utf8.decode(response.bodyBytes)) as List)
            .cast<Map<String, dynamic>>();
      });
    } catch (_) {}
  }

  Future<void> _likePost(String postId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final actionKey = 'like:$postId';
    if (userId == null || !_pendingPostActions.add(actionKey)) return;
    _updateFeedPost(postId, (post) {
      final liked = post['liked'] == true;
      return {
        ...post,
        'liked': !liked,
        'likes': ((post['likes'] as num?)?.toInt() ?? 0) + (liked ? -1 : 1),
      };
    });
    try {
      final response = await http.post(
        Uri.parse('$_api/api/profiles/posts/$postId/like'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId}),
      );
      if (response.statusCode != 200) throw Exception();
    } catch (_) {
      await _loadFeedPosts();
    } finally {
      _pendingPostActions.remove(actionKey);
    }
  }

  Future<void> _commentPost(String postId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: .78,
        child: _CommentsSheet(postId: postId, userId: userId),
      ),
    );
    await _loadFeedPosts();
  }

  Future<void> _repost(String postId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final actionKey = 'repost:$postId';
    if (userId == null || !_pendingPostActions.add(actionKey)) return;
    var wasReposted = false;
    _updateFeedPost(postId, (post) {
      wasReposted = post['reposted'] == true;
      return {
        ...post,
        'reposted': !wasReposted,
        'reposts':
            ((post['reposts'] as num?)?.toInt() ?? 0) + (wasReposted ? -1 : 1),
      };
    });
    try {
      final response = await http.post(
        Uri.parse('$_api/api/profiles/posts/$postId/repost'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId}),
      );
      if (response.statusCode != 200) throw Exception();
      AppFeedback.success(
          wasReposted ? 'Repost eliminado.' : 'Publicación reposteada.');
    } catch (_) {
      await _loadFeedPosts();
    } finally {
      _pendingPostActions.remove(actionKey);
    }
  }

  void _updateFeedPost(String postId,
      Map<String, dynamic> Function(Map<String, dynamic>) update) {
    if (!mounted) return;
    setState(() {
      _feedPosts = _feedPosts
          .map((post) => '${post['id']}' == postId ? update(post) : post)
          .toList();
    });
  }

  String _postTime(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return 'ahora';
    final elapsed = DateTime.now().difference(date);
    if (elapsed.inMinutes < 1) return 'ahora';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min';
    if (elapsed.inHours < 24) return '${elapsed.inHours} h';
    return '${elapsed.inDays} d';
  }

  Future<void> _openNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    final profileName = '${_currentProfile?['username'] ?? ''}'.trim();
    final accountName = profileName.isNotEmpty
        ? profileName
        : (user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!.trim()
            : (user?.email?.split('@').first ?? 'XpertCommunity'));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsPage(accountName: accountName),
      ),
    );
  }

  Future<void> _openMessages() async {
    final user = FirebaseAuth.instance.currentUser;
    final username = '${_currentProfile?['username'] ?? ''}'.trim();
    final accountName = username.isNotEmpty
        ? username
        : (user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!.trim()
            : (user?.email?.split('@').first ?? 'XpertCommunity'));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessagesPage(accountName: accountName),
      ),
    );
  }

  Widget _buildFeedPost(Map<String, dynamic> post) {
    final author = post['author'] as Map<String, dynamic>? ?? const {};
    final images = author['images'] as Map<String, dynamic>?;
    final avatar = images?['avatar'] as Map<String, dynamic>?;
    final postId = '${post['id'] ?? ''}';
    final authorId = '${post['userId'] ?? ''}';
    final name = '${author['name'] ?? author['username'] ?? 'Piloto'}';
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();
    return RepaintBoundary(
      key: ValueKey(postId),
      child: _Post(
        avatarColor: const Color(0xFF555555),
        avatarUrl: avatar == null
            ? null
            : '$_api/api/profiles/$authorId/images/avatar?v=${avatar['uploadedAt'] ?? ''}',
        initials: initials,
        username: name,
        time: _postTime('${post['createdAt'] ?? ''}'),
        category: 'XpertCommunity',
        text: '${post['content'] ?? ''}',
        imageUrl: post['hasImage'] == true
            ? '$_api/api/profiles/posts/$postId/media'
            : null,
        likes: (post['likes'] as num?)?.toInt() ?? 0,
        replies: (post['comments'] as num?)?.toInt() ?? 0,
        reposts: (post['reposts'] as num?)?.toInt() ?? 0,
        liked: post['liked'] == true,
        onLike: () => _likePost(postId),
        onComment: () => _commentPost(postId),
        onRepost: () => _repost(postId),
      ),
    );
  }

  Widget _buildDemoPost(int index) {
    const demos = [
      (
        initials: 'SC',
        color: Color(0xFF111111),
        username: 'skycam.co',
        time: '2 h',
        category: 'Fotografía aérea',
        text:
            'La neblina abrió por cinco minutos y alcanzamos a capturar esta vista. ¿Quién más ha volado en el Valle del Cocora?',
        likes: 128,
        replies: 18,
      ),
      (
        initials: 'LM',
        color: Color(0xFF59636D),
        username: 'luism.pilot',
        time: '5 h',
        category: 'Pilotos FPV',
        text:
            'Primer vuelo con configuración manual. Todavía ajustando rates, pero la sensación de control cambia por completo.',
        likes: 74,
        replies: 9,
      ),
      (
        initials: 'AR',
        color: Color(0xFFB4B4B4),
        username: 'ana.rojas',
        time: '8 h',
        category: 'Consejos',
        text:
            'Antes de despegar revisen siempre viento, baterías y restricciones de la zona. Una buena toma comienza con un vuelo seguro.',
        likes: 203,
        replies: 31,
      ),
    ];
    final demo = demos[index];
    final liked = _likedDemoPosts.contains(index);
    return RepaintBoundary(
      key: ValueKey('demo-$index'),
      child: _Post(
        avatarColor: demo.color,
        initials: demo.initials,
        username: demo.username,
        time: demo.time,
        category: demo.category,
        text: demo.text,
        likes: demo.likes + (liked ? 1 : 0),
        replies: demo.replies,
        liked: liked,
        onLike: () => setState(() {
          if (!_likedDemoPosts.add(index)) _likedDemoPosts.remove(index);
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.white,
      body: _selectedIndex == 4
          ? PilotProfileRedesignPage(
              onCompose: (name, avatarBytes) => _showComposer(
                context,
                initialName: name,
                initialAvatarBytes: avatarBytes,
              ),
            )
          : CustomScrollView(
              scrollCacheExtent: const ScrollCacheExtent.pixels(900),
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  floating: true,
                  snap: true,
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  toolbarHeight: 64,
                  leading: IconButton(
                    tooltip: 'Menú',
                    onPressed: () => _showMainMenu(context),
                    icon: const Icon(PhosphorIconsRegular.list, size: 28),
                  ),
                  titleSpacing: 0,
                  title: const Text(
                    'XpertCommunity',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                    ),
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'Notificaciones',
                      onPressed: _openNotifications,
                      icon: const Icon(PhosphorIconsRegular.bell, size: 26),
                    ),
                    IconButton(
                      tooltip: 'Buscar',
                      onPressed: () => AppFeedback.info(
                        'La búsqueda estará disponible próximamente.',
                      ),
                      icon: const Icon(
                        PhosphorIconsRegular.magnifyingGlass,
                        size: 27,
                      ),
                    ),
                    _ChatButton(onPressed: _openMessages),
                    const SizedBox(width: 4),
                  ],
                  bottom: const PreferredSize(
                    preferredSize: Size.fromHeight(1),
                    child: Divider(height: 1, color: Color(0xFFEAEAEA)),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(children: [
                    _StoriesStrip(
                      currentProfile: _currentProfile,
                      stories: [..._activeStories, ..._demoStories],
                      onCreate: () => setState(() => _selectedIndex = 4),
                      onOpen: _openFeedStory,
                    ),
                    const Divider(
                        height: 9, thickness: 8, color: Color(0xFFF0F0F0)),
                  ]),
                ),
                SliverList.builder(
                  itemCount: _feedPosts.length + 3,
                  itemBuilder: (_, index) => index < _feedPosts.length
                      ? _buildFeedPost(_feedPosts[index])
                      : _buildDemoPost(index - _feedPosts.length),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
      bottomNavigationBar: _FeedBottomBar(
        selectedIndex: _selectedIndex,
        onSelected: (index) {
          if (index == 3) {
            _openNotifications();
            return;
          }
          setState(() => _selectedIndex = index);
        },
        onCompose: () => _showComposer(context),
        onReels: () => _showReelComposer(context),
      ),
    );
  }

  Future<bool> _showComposer(
    BuildContext context, {
    String? initialName,
    Uint8List? initialAvatarBytes,
  }) async {
    final published = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black26,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
          ),
          builder: (_) => FractionallySizedBox(
            heightFactor: .94,
            child: _ComposerPage(
              initialName: initialName,
              initialAvatarBytes: initialAvatarBytes,
            ),
          ),
        ) ??
        false;
    if (published) await _loadFeedPosts();
    return published;
  }

  void _showReelComposer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD8D8D8),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 22),
          const Icon(PhosphorIconsRegular.filmSlate, size: 34),
          const SizedBox(height: 12),
          const Text(
            'Crear reel',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          const Text(
            'Selecciona un video de tu dispositivo para compartirlo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF6F6F6F)),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                AppFeedback.info(
                    'El selector de videos estará disponible próximamente.');
              },
              icon: const Icon(PhosphorIconsRegular.uploadSimple),
              label: const Text('Seleccionar video'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _showMainMenu(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar menú',
      barrierColor: const Color(0x33000000),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return SlideTransition(position: slide, child: child);
      },
      pageBuilder: (dialogContext, animation, secondaryAnimation) => Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: Colors.white,
          borderRadius:
              const BorderRadius.horizontal(right: Radius.circular(30)),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width * .82,
              height: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Expanded(
                          child: Text('Feeds',
                              style: TextStyle(
                                  fontSize: 28, fontWeight: FontWeight.w400)),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(PhosphorIconsRegular.x),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(
                            child: _menuShortcut(PhosphorIconsRegular.heart)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _menuShortcut(
                                PhosphorIconsRegular.bookmarkSimple)),
                      ]),
                      const SizedBox(height: 22),
                      _menuItem(dialogContext, 'Para ti'),
                      _menuItem(dialogContext, 'Seguidos'),
                      _menuItem(dialogContext, 'Publicaciones temporales',
                          icon: PhosphorIconsRegular.smiley),
                      const Spacer(),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F1F1),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: ListTile(
                          leading: const Icon(PhosphorIconsRegular.gearSix),
                          title: const Text('Configuración'),
                          onTap: () =>
                              AppFeedback.info('Configuración: próximamente.'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F1F1),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: ListTile(
                          leading: const Icon(PhosphorIconsRegular.signOut),
                          title: const Text('Cerrar sesión', maxLines: 1),
                          onTap: () async {
                            Navigator.pop(dialogContext);
                            final confirmed = await AppFeedback.confirmDelete(
                              context,
                              itemName: 'la sesión',
                            );
                            if (!confirmed) return;
                            _presenceTimer?.cancel();
                            await _updatePresence(false);
                            await GoogleSignIn.instance.signOut();
                            await FirebaseAuth.instance.signOut();
                          },
                        ),
                      ),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuShortcut(IconData icon) => Container(
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, size: 25),
      );

  Widget _menuItem(BuildContext context, String label, {IconData? icon}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(18),
        ),
        child: ListTile(
          minTileHeight: 60,
          title: Text(label, maxLines: 1, style: const TextStyle(fontSize: 16)),
          trailing: icon == null ? null : Icon(icon),
          onTap: () => Navigator.pop(context),
        ),
      );
}

class _ComposerPage extends StatefulWidget {
  const _ComposerPage({this.initialName, this.initialAvatarBytes});

  final String? initialName;
  final Uint8List? initialAvatarBytes;

  @override
  State<_ComposerPage> createState() => _ComposerPageState();
}

class _ComposerPageState extends State<_ComposerPage> {
  final _focusNode = FocusNode();
  final _contentController = TextEditingController();
  String _displayName = 'Usuario';
  String? _avatarUrl;
  Uint8List? _avatarBytes;
  Uint8List? _postImageBytes;
  String? _postImageName;
  MediaType? _postImageType;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    final initialName = widget.initialName?.trim();
    if (initialName != null && initialName.isNotEmpty) {
      _displayName = initialName;
    }
    _avatarBytes = widget.initialAvatarBytes;
    _loadAuthor();
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _loadAuthor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final fallbackName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? 'Usuario');
    if (mounted && (widget.initialName?.trim().isEmpty ?? true)) {
      setState(() => _displayName = fallbackName);
    }
    try {
      final response = await http
          .get(Uri.parse('$_api/api/profiles/${user.uid}'))
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200 || !mounted) return;
      final profile =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final name = '${profile['name'] ?? ''}'.trim();
      final images = profile['images'] as Map<String, dynamic>?;
      final avatar = images?['avatar'] as Map<String, dynamic>?;
      setState(() {
        if (name.isNotEmpty) _displayName = name;
        if (avatar != null) {
          _avatarUrl =
              '$_api/api/profiles/${user.uid}/images/avatar?v=${avatar['uploadedAt'] ?? ''}';
        }
      });
    } catch (_) {}
  }

  String get _initials => _displayName
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0])
      .join()
      .toUpperCase();

  Future<void> _publish() async {
    final content = _contentController.text.trim();
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (content.isEmpty && _postImageBytes == null) {
      AppFeedback.info('Escribe algo o selecciona una imagen.');
      return;
    }
    if (userId == null || _publishing) return;
    FocusScope.of(context).unfocus();
    setState(() => _publishing = true);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_api/api/profiles/$userId/posts'),
      )..fields['content'] = content;
      final imageBytes = _postImageBytes;
      if (imageBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: _postImageName,
          contentType: _postImageType,
        ));
      }
      final response =
          await request.send().timeout(const Duration(seconds: 45));
      if (response.statusCode != 201) throw Exception();
      AppFeedback.success('Publicación guardada.');
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _publishing = false);
      AppFeedback.error('No fue posible publicar.');
    }
  }

  Future<void> _pickPostImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null || !mounted) return;
    final length = await file.length();
    if (length == null || length > 10 * 1024 * 1024) {
      AppFeedback.info('La imagen no puede superar 10 MB.');
      return;
    }
    final extension = (file.extension ?? 'jpg').toLowerCase();
    final subtype = extension == 'jpg' ? 'jpeg' : extension;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _postImageBytes = bytes;
      _postImageName = file.name;
      _postImageType = MediaType('image', subtype);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 94,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          child: const Text(
            'Cancelar',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
          ),
        ),
        title: const Text(
          'Nuevo hilo',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Borradores',
            onPressed: () {},
            icon: const Icon(PhosphorIconsRegular.notePencil),
          ),
          IconButton(
            tooltip: 'Más opciones',
            onPressed: () {},
            icon: const Icon(PhosphorIconsRegular.dotsThree),
          ),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFEAEAEA)),
        ),
      ),
      body: AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: const Color(0xFF747D86),
                    backgroundImage: _avatarBytes != null
                        ? MemoryImage(_avatarBytes!)
                        : (_avatarUrl == null
                            ? null
                            : NetworkImage(_avatarUrl!)),
                    child: _avatarBytes == null && _avatarUrl == null
                        ? Text(
                            _initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              flex: 2,
                              child: Text(
                                _displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(PhosphorIconsRegular.caretRight,
                                size: 16),
                            const Expanded(
                              child: Text(
                                'Comunidad o tema',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xFF999999),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TextField(
                          controller: _contentController,
                          focusNode: _focusNode,
                          onChanged: (_) => setState(() {}),
                          minLines: 2,
                          maxLines: 5,
                          scrollPadding: EdgeInsets.zero,
                          decoration: const InputDecoration(
                            hintText: '¿Qué novedades tienes?',
                            hintStyle: TextStyle(
                              color: Color(0xFFAAAAAA),
                              fontSize: 16,
                            ),
                            contentPadding: EdgeInsets.only(top: 4),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                        ),
                        if (_postImageBytes != null) ...[
                          const SizedBox(height: 8),
                          Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                _postImageBytes!,
                                height: 170,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: IconButton.filled(
                                onPressed: () => setState(() {
                                  _postImageBytes = null;
                                  _postImageName = null;
                                  _postImageType = null;
                                }),
                                icon: const Icon(PhosphorIconsRegular.x),
                              ),
                            ),
                          ]),
                        ],
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Foto',
                              onPressed: _pickPostImage,
                              icon: const Icon(PhosphorIconsRegular.image),
                            ),
                            IconButton(
                              tooltip: 'GIF',
                              onPressed: () {},
                              icon: const Icon(PhosphorIconsRegular.gif),
                            ),
                            IconButton(
                              tooltip: 'Ubicación',
                              onPressed: () {},
                              icon: const Icon(PhosphorIconsRegular.mapPin),
                            ),
                            IconButton(
                              tooltip: 'Más',
                              onPressed: () {},
                              icon: const Icon(PhosphorIconsRegular.dotsThree),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(left: 22, top: 6),
                child: Text(
                  '＋  Agregar al hilo',
                  style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 13),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(
                    PhosphorIconsRegular.slidersHorizontal,
                    color: Color(0xFF777777),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Opciones de la publicación',
                      style: TextStyle(color: Color(0xFF777777), fontSize: 13),
                    ),
                  ),
                  FilledButton(
                    onPressed: _publishing ? null : _publish,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                    ),
                    child: _publishing
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Publicar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatButton extends StatelessWidget {
  const _ChatButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Chat',
          onPressed: onPressed,
          icon: const Icon(PhosphorIconsRegular.chatCircleDots, size: 27),
        ),
        Positioned(
          right: 3,
          top: 2,
          child: Container(
            width: 17,
            height: 17,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFE51C46),
              shape: BoxShape.circle,
            ),
            child: const Text(
              '2',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DemoStoryPage extends StatefulWidget {
  const _DemoStoryPage({required this.story});

  final Map<String, dynamic> story;

  @override
  State<_DemoStoryPage> createState() => _DemoStoryPageState();
}

class _DemoStoryPageState extends State<_DemoStoryPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          Navigator.pop(context);
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.story['color'] as int);
    final name = '${widget.story['name'] ?? 'Piloto UAS'}';
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => _progress.stop(),
        onLongPressEnd: (_) => _progress.forward(),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: .95), Colors.black],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 22),
              child: Column(children: [
                AnimatedBuilder(
                  animation: _progress,
                  builder: (_, __) => LinearProgressIndicator(
                    value: _progress.value,
                    minHeight: 2.5,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white24,
                    child: Text(initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(PhosphorIconsRegular.x,
                        color: Colors.white, size: 24),
                  ),
                ]),
                const Spacer(),
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(PhosphorIconsRegular.airplaneTilt,
                      color: Colors.white, size: 48),
                ),
                const SizedBox(height: 24),
                Text(
                  '${widget.story['caption'] ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Mantén presionado para pausar',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoriesStrip extends StatelessWidget {
  const _StoriesStrip({
    required this.currentProfile,
    required this.stories,
    required this.onCreate,
    required this.onOpen,
  });

  final Map<String, dynamic>? currentProfile;
  final List<Map<String, dynamic>> stories;
  final VoidCallback onCreate;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) {
    final currentId = '${currentProfile?['userId'] ?? ''}';
    final ownStory = stories.cast<Map<String, dynamic>?>().firstWhere(
          (item) => '${item?['userId'] ?? ''}' == currentId,
          orElse: () => null,
        );
    final others = stories
        .where((item) => '${item['userId'] ?? ''}' != currentId)
        .toList();
    return SizedBox(
      height: 138,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        itemCount: others.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _StoryBubble(
              profile: ownStory ?? currentProfile,
              label: 'Tu historia',
              hasStory: ownStory != null,
              showAdd: ownStory == null,
              onTap: ownStory == null ? onCreate : () => onOpen(ownStory),
            );
          }
          final story = others[index - 1];
          return _StoryBubble(
            profile: story,
            label: '${story['username'] ?? story['name'] ?? 'Piloto'}',
            hasStory: true,
            onTap: () => onOpen(story),
          );
        },
      ),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({
    required this.profile,
    required this.label,
    required this.hasStory,
    required this.onTap,
    this.showAdd = false,
  });

  final Map<String, dynamic>? profile;
  final String label;
  final bool hasStory;
  final bool showAdd;
  final VoidCallback onTap;

  String get _initials => '${profile?['name'] ?? 'P'}'
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0])
      .join()
      .toUpperCase();

  String? get _avatarUrl {
    final userId = '${profile?['userId'] ?? ''}';
    final images = profile?['images'] as Map<String, dynamic>?;
    final avatar = images?['avatar'] as Map<String, dynamic>?;
    if (userId.isEmpty || avatar == null) return null;
    return '$_api/api/profiles/$userId/images/avatar?v=${avatar['uploadedAt'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _avatarUrl;
    return SizedBox(
      width: 90,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 86,
              height: 86,
              padding: EdgeInsets.all(hasStory ? 3.5 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: hasStory
                    ? Border.all(color: const Color(0xFF1473E6), width: 3.5)
                    : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: CircleAvatar(
                  backgroundColor: const Color(0xFF777777),
                  backgroundImage:
                      avatarUrl == null ? null : NetworkImage(avatarUrl),
                  child: avatarUrl == null
                      ? Text(_initials,
                          style: const TextStyle(color: Colors.white))
                      : null,
                ),
              ),
            ),
            if (showAdd)
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 29,
                  height: 29,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(PhosphorIconsRegular.plus,
                      color: Colors.white, size: 18),
                ),
              ),
          ]),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ]),
      ),
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.postId, required this.userId});

  final String postId;
  final String userId;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  bool _changed = false;

  static const _emojis = ['❤️', '🙌', '🔥', '👏', '😢', '😍', '😮', '😂'];

  @override
  void initState() {
    super.initState();
    unawaited(_loadComments());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final response = await http
          .get(Uri.parse('$_api/api/profiles/posts/${widget.postId}/comments'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw Exception();
      final comments = (jsonDecode(utf8.decode(response.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppFeedback.error('No pudimos cargar los comentarios.');
    }
  }

  Future<void> _sendComment() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_api/api/profiles/posts/${widget.postId}/comments'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'userId': widget.userId, 'content': content}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 201) throw Exception();
      _controller.clear();
      _changed = true;
      await _loadComments();
    } catch (_) {
      AppFeedback.error('No pudimos publicar el comentario.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _elapsed(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return 'ahora';
    final elapsed = DateTime.now().difference(date);
    if (elapsed.inMinutes < 1) return 'ahora';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min';
    if (elapsed.inHours < 24) return '${elapsed.inHours} h';
    return '${elapsed.inDays} d';
  }

  String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part[0])
      .join()
      .toUpperCase();

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentName = currentUser?.displayName?.trim();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 9),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFB9B9B9),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 9, 8, 7),
              child: Row(
                children: [
                  const SizedBox(width: 42),
                  const Expanded(
                    child: Text(
                      'Comentarios',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context, _changed),
                    icon: const Icon(PhosphorIconsRegular.x, size: 23),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE9E9E9)),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black))
                  : _comments.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIconsRegular.chatCircleDots,
                                  size: 42, color: Color(0xFF8A8A8A)),
                              SizedBox(height: 12),
                              Text('Sé el primero en comentar',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500)),
                              SizedBox(height: 5),
                              Text('Comparte lo que piensas.',
                                  style: TextStyle(
                                      fontSize: 13, color: Color(0xFF888888))),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 18, 14, 22),
                          itemCount: _comments.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 18),
                          itemBuilder: (context, index) {
                            final comment = _comments[index];
                            final author =
                                comment['author'] as Map<String, dynamic>? ??
                                    const {};
                            final userId = '${comment['userId'] ?? ''}';
                            final name =
                                '${author['name'] ?? author['username'] ?? 'Piloto'}';
                            final images =
                                author['images'] as Map<String, dynamic>?;
                            final avatar =
                                images?['avatar'] as Map<String, dynamic>?;
                            final avatarUrl = avatar == null
                                ? null
                                : '$_api/api/profiles/$userId/images/avatar?v=${avatar['uploadedAt'] ?? ''}';
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFF6D6D6D),
                                  backgroundImage: avatarUrl == null
                                      ? null
                                      : NetworkImage(avatarUrl),
                                  child: avatarUrl == null
                                      ? Text(_initials(name),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11))
                                      : null,
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text.rich(
                                        TextSpan(children: [
                                          TextSpan(
                                            text: name,
                                            style: const TextStyle(
                                                color: Colors.black,
                                                fontWeight: FontWeight.w500),
                                          ),
                                          TextSpan(
                                            text:
                                                '  ${_elapsed('${comment['createdAt'] ?? ''}')}',
                                            style: const TextStyle(
                                                color: Color(0xFF929292)),
                                          ),
                                        ]),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('${comment['content'] ?? ''}',
                                          style: const TextStyle(
                                              fontSize: 14, height: 1.3)),
                                      const SizedBox(height: 5),
                                      GestureDetector(
                                        onTap: () {
                                          _controller.text = '@$name ';
                                          _controller.selection =
                                              TextSelection.collapsed(
                                                  offset:
                                                      _controller.text.length);
                                          _focusNode.requestFocus();
                                        },
                                        child: const Text('Responder',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF777777),
                                                fontWeight: FontWeight.w500)),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Me gusta',
                                  onPressed: () {},
                                  icon: const Icon(PhosphorIconsRegular.heart,
                                      size: 19),
                                ),
                              ],
                            );
                          },
                        ),
            ),
            const Divider(height: 1, color: Color(0xFFE9E9E9)),
            SizedBox(
              height: 54,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 17),
                itemCount: _emojis.length,
                separatorBuilder: (_, __) => const SizedBox(width: 19),
                itemBuilder: (_, index) => InkWell(
                  onTap: () {
                    final selection = _controller.selection;
                    final offset = selection.isValid
                        ? selection.baseOffset
                        : _controller.text.length;
                    _controller.text = _controller.text
                        .replaceRange(offset, offset, _emojis[index]);
                    _controller.selection = TextSelection.collapsed(
                        offset: offset + _emojis[index].length);
                    _focusNode.requestFocus();
                  },
                  child: Center(
                    child: Text(_emojis[index],
                        style: const TextStyle(fontSize: 25)),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: const Color(0xFF606060),
                    child: Text(
                      _initials(currentName?.isNotEmpty == true
                          ? currentName!
                          : 'Tú'),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendComment(),
                      decoration: InputDecoration(
                        hintText: 'Agrega un comentario...',
                        hintStyle: const TextStyle(
                            color: Color(0xFF8A8A8A), fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFFF3F3F3),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 11),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.black),
                                ),
                              )
                            : IconButton(
                                tooltip: 'Publicar comentario',
                                onPressed: _sendComment,
                                icon: const Icon(
                                    PhosphorIconsFill.paperPlaneTilt,
                                    size: 21),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Post extends StatelessWidget {
  const _Post({
    required this.avatarColor,
    required this.initials,
    required this.username,
    required this.time,
    required this.category,
    required this.text,
    required this.likes,
    required this.replies,
    required this.liked,
    required this.onLike,
    this.avatarUrl,
    this.imageUrl,
    this.reposts = 0,
    this.onComment,
    this.onRepost,
  });

  final Color avatarColor;
  final String? avatarUrl;
  final String? imageUrl;
  final String initials;
  final String username;
  final String time;
  final String category;
  final String text;
  final int likes;
  final int replies;
  final int reposts;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback? onComment;
  final VoidCallback? onRepost;

  @override
  Widget build(BuildContext context) {
    final imageCacheWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(480, 1440);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 16, 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFECECEC))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: avatarColor,
                backgroundImage: avatarUrl == null
                    ? null
                    : ResizeImage(NetworkImage(avatarUrl!), width: 120),
                child: avatarUrl == null
                    ? Text(initials,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12))
                    : null,
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PostHeader(
                  username: username,
                  time: time,
                  category: category,
                ),
                const SizedBox(height: 9),
                Text(text, style: const TextStyle(fontSize: 14, height: 1.35)),
                if (imageUrl != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.network(
                        imageUrl!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        cacheWidth: imageCacheWidth,
                        filterQuality: FilterQuality.low,
                        gaplessPlayback: true,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                                ? child
                                : const ColoredBox(color: Color(0xFFF3F3F3)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 13),
                _PostActions(
                  liked: liked,
                  likes: likes,
                  replies: replies,
                  reposts: reposts,
                  onLike: onLike,
                  onComment: onComment,
                  onRepost: onRepost,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  const _PostHeader({
    required this.username,
    required this.time,
    required this.category,
  });

  final String username;
  final String time;
  final String category;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: username,
                      style: const TextStyle(fontWeight: FontWeight.w400),
                    ),
                    TextSpan(
                      text: '  $time',
                      style: const TextStyle(color: Color(0xFF929292)),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                category,
                style: const TextStyle(color: Color(0xFF929292), fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {},
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            PhosphorIconsRegular.dotsThree,
            color: Color(0xFF777777),
          ),
        ),
      ],
    );
  }
}

class _PostActions extends StatelessWidget {
  const _PostActions({
    required this.liked,
    required this.likes,
    required this.replies,
    required this.onLike,
    this.reposts = 0,
    this.onComment,
    this.onRepost,
  });

  final bool liked;
  final int likes;
  final int replies;
  final int reposts;
  final VoidCallback onLike;
  final VoidCallback? onComment;
  final VoidCallback? onRepost;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Action(
          icon: liked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
          label: '$likes',
          color: liked ? const Color(0xFFE61F4D) : Colors.black87,
          onTap: onLike,
        ),
        const SizedBox(width: 20),
        _Action(
          icon: PhosphorIconsRegular.chatCircle,
          label: '$replies',
          onTap: onComment ?? () {},
        ),
        const SizedBox(width: 20),
        _Action(
          icon: PhosphorIconsRegular.repeat,
          label: reposts == 0 ? null : '$reposts',
          onTap: onRepost ?? () {},
        ),
        const SizedBox(width: 20),
        _Action(icon: PhosphorIconsRegular.paperPlaneTilt, onTap: () {}),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.onTap,
    this.label,
    this.color = Colors.black87,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 23, color: color),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(label!, style: TextStyle(color: color, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedBottomBar extends StatelessWidget {
  const _FeedBottomBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.onCompose,
    required this.onReels,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onCompose;
  final VoidCallback onReels;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 6, 18, 8),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFF0F0F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 20,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navIcon(
              index: 0,
              icon: PhosphorIconsRegular.house,
              selectedIcon: PhosphorIconsFill.house,
              tooltip: 'Inicio',
            ),
            IconButton(
              tooltip: 'Crear reel',
              onPressed: onReels,
              icon: const Icon(PhosphorIconsRegular.filmSlate, size: 25),
            ),
            IconButton(
              tooltip: 'Crear publicación',
              onPressed: onCompose,
              icon: const Icon(PhosphorIconsRegular.plus, size: 29),
            ),
            _navIcon(
              index: 3,
              icon: PhosphorIconsRegular.bell,
              selectedIcon: PhosphorIconsFill.bell,
              tooltip: 'Notificaciones',
              notification: true,
            ),
            _navIcon(
              index: 4,
              icon: PhosphorIconsRegular.user,
              selectedIcon: PhosphorIconsFill.user,
              tooltip: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }

  Widget _navIcon({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String tooltip,
    bool notification = false,
  }) {
    final selected = selectedIndex == index;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onSelected(index),
        borderRadius: BorderRadius.circular(23),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: selected ? 52 : 42,
          height: 44,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEDEDED) : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 25,
                  color: const Color(0xFF171717),
                ),
                if (notification)
                  Positioned(
                    right: -2,
                    top: -1,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF1744),
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 1.5),
                        ),
                      ),
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
