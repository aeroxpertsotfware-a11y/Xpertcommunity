import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:phosphor_icons/phosphor_icons.dart';

const _demoConversations = [
  _Conversation(
      'Germán Alexis Vanegas', 'Jajaja siii', '5 h', 'GA', Color(0xFF887264),
      unread: true),
  _Conversation('M!el', '🤣', '9 h', 'ME', Color(0xFFB56C78)),
  _Conversation('Esteban Gonzalez Londoño', 'Activo(a) ahora', '', 'EG',
      Color(0xFF3A718A),
      online: true),
  _Conversation(
      'aeroxpert_uas', 'Usuario activo hace 4 h', '', 'AU', Color(0xFF168FC4)),
  _Conversation('quetacosgourmet', 'Enviado', '', 'QG', Color(0xFF658B52)),
  _Conversation('Balbony ®', 'Activo(a) ahora', '', 'BB', Color(0xFF171717),
      online: true),
  _Conversation('Pilotos Colombia', 'Nuevo encuentro UAS', '1 d', 'PC',
      Color(0xFF815D9A)),
];

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key, required this.accountName});
  final String accountName;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final conversations = _demoConversations
        .where((item) =>
            item.name.toLowerCase().contains(_query.trim().toLowerCase()))
        .toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsRegular.caretLeft, size: 23),
        ),
        title: Text(widget.accountName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Nuevo mensaje',
            onPressed: () {},
            icon: const Icon(PhosphorIconsRegular.notePencil, size: 25),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: CustomScrollView(
        scrollCacheExtent: const ScrollCacheExtent.pixels(700),
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 5, 16, 12),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Buscar',
                  prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass,
                      size: 21),
                  filled: true,
                  fillColor: const Color(0xFFF1F3F5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: _NotesStrip()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
              child: Row(children: [
                const Text('Mensajes',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () {},
                  child: const Text('Solicitudes',
                      style: TextStyle(
                          color: Color(0xFF666666),
                          fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
          ),
          if (conversations.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 70),
                child: Center(child: Text('No encontramos conversaciones')),
              ),
            )
          else
            SliverList.builder(
              itemCount: conversations.length,
              itemBuilder: (_, index) {
                final item = conversations[index];
                return _ConversationTile(
                  conversation: item,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ChatPage(conversation: item),
                    ),
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ],
      ),
    );
  }
}

class _NotesStrip extends StatelessWidget {
  const _NotesStrip();

  @override
  Widget build(BuildContext context) {
    const notes = [
      ('Tu nota', 'Tú', Color(0xFF777777)),
      ('Mapa', 'MP', Color(0xFF69A7C8)),
      ('Esteban', 'EG', Color(0xFF3A718A)),
      ('Mauricio', 'MC', Color(0xFFB79730)),
    ];
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: notes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 15),
        itemBuilder: (_, index) {
          final note = notes[index];
          return SizedBox(
            width: 78,
            child: Column(children: [
              Stack(clipBehavior: Clip.none, children: [
                _MessageAvatar(initials: note.$2, color: note.$3, size: 68),
                if (index == 0)
                  Positioned(
                    right: -2,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: const [
                          BoxShadow(color: Color(0x18000000), blurRadius: 7)
                        ],
                      ),
                      child: const Text('Comparte\nuna nota',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 9, color: Color(0xFF666666))),
                    ),
                  ),
              ]),
              const SizedBox(height: 7),
              Text(note.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ]),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});
  final _Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              _MessageAvatar(
                  initials: conversation.initials,
                  color: conversation.color,
                  size: 58),
              if (conversation.online)
                Positioned(
                  right: 0,
                  bottom: 1,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16C85B),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conversation.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: conversation.unread
                                ? FontWeight.w600
                                : FontWeight.w400)),
                    const SizedBox(height: 3),
                    Text(
                      [conversation.preview, conversation.time]
                          .where((value) => value.isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: conversation.unread
                            ? const Color(0xFF222222)
                            : const Color(0xFF7B7B7B),
                        fontWeight: conversation.unread
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                  ]),
            ),
            if (conversation.unread)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: Color(0xFF5865F2), shape: BoxShape.circle),
              ),
          ]),
        ),
      );
}

class _ChatPage extends StatefulWidget {
  const _ChatPage({required this.conversation});
  final _Conversation conversation;

  @override
  State<_ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<_ChatPage> {
  final _controller = TextEditingController();
  final List<String> _sentMessages = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sentMessages.add(text));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.conversation;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(PhosphorIconsRegular.caretLeft, size: 23),
        ),
        titleSpacing: 0,
        title: Row(children: [
          _MessageAvatar(
              initials: person.initials, color: person.color, size: 38),
          const SizedBox(width: 9),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const Text('Usuario activo hace 17 min',
                  style: TextStyle(fontSize: 11, color: Color(0xFF666666))),
            ]),
          ),
        ]),
        actions: [
          IconButton(
              onPressed: () {},
              icon: const Icon(PhosphorIconsRegular.phone, size: 25)),
          IconButton(
              onPressed: () {},
              icon: const Icon(PhosphorIconsRegular.videoCamera, size: 26)),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              ..._sentMessages.reversed.map(
                (message) => _ChatBubble(text: message, mine: true),
              ),
              const _ChatBubble(text: 'Jajaja siii', mine: false),
              const _NewMessagesDivider(),
              const _ChatBubble(text: 'Es famosa', mine: true),
              const _ChatBubble(text: 'Jajajajajajja', mine: true),
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('12:38 P.M.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF777777))),
                ),
              ),
              const _ChatBubble(text: 'Ajueeeeeee', mine: false),
              const _DemoMediaMessage(),
              const _ChatBubble(text: 'Negro no creo', mine: false),
            ],
          ),
        ),
        _MessageComposer(controller: _controller, onSend: _send),
      ]),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text, required this.mine});
  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .72),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? const Color(0xFF6E35E8) : const Color(0xFFF0F2F4),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(text,
              style: TextStyle(
                  color: mine ? Colors.white : Colors.black,
                  fontSize: 14,
                  height: 1.2)),
        ),
      );
}

class _DemoMediaMessage extends StatelessWidget {
  const _DemoMediaMessage();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 210,
          height: 280,
          margin: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF91BDD0), Color(0xFF243A49)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(PhosphorIconsRegular.image, color: Colors.white, size: 42),
                SizedBox(height: 10),
                Text('Contenido multimedia de prueba',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ]),
        ),
      );
}

class _NewMessagesDivider extends StatelessWidget {
  const _NewMessagesDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Expanded(child: Divider()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('Nuevos mensajes',
                style: TextStyle(fontSize: 11, color: Color(0xFF777777))),
          ),
          Expanded(child: Divider()),
        ]),
      );
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F5),
              borderRadius: BorderRadius.circular(27),
            ),
            child: Row(children: [
              IconButton(
                  onPressed: () {},
                  icon: const Icon(PhosphorIconsFill.camera,
                      color: Color(0xFF6657EE))),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Mensaje...',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              IconButton(
                  onPressed: () {},
                  icon: const Icon(PhosphorIconsRegular.microphone, size: 22)),
              IconButton(
                  onPressed: onSend,
                  icon: const Icon(PhosphorIconsRegular.paperPlaneTilt,
                      size: 22)),
            ]),
          ),
        ),
      );
}

class _MessageAvatar extends StatelessWidget {
  const _MessageAvatar(
      {required this.initials, required this.color, required this.size});
  final String initials;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(initials,
            style: TextStyle(
                color: Colors.white,
                fontSize: size * .25,
                fontWeight: FontWeight.w600)),
      );
}

class _Conversation {
  const _Conversation(
      this.name, this.preview, this.time, this.initials, this.color,
      {this.online = false, this.unread = false});
  final String name;
  final String preview;
  final String time;
  final String initials;
  final Color color;
  final bool online;
  final bool unread;
}
