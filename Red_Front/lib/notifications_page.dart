import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:phosphor_icons/phosphor_icons.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key, required this.accountName});

  final String accountName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(700),
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              toolbarHeight: 54,
              leadingWidth: 54,
              leading: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: IconButton(
                  tooltip: 'Volver',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(PhosphorIconsRegular.caretLeft, size: 22),
                ),
              ),
              titleSpacing: 2,
              title: Text(
                accountName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -.2,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Configurar notificaciones',
                  onPressed: () {},
                  icon: const Icon(PhosphorIconsRegular.bell, size: 23),
                ),
                const SizedBox(width: 4),
              ],
            ),
            SliverToBoxAdapter(
              child: _FollowerRequestsTile(
                onTap: () => _showMessage(context, 'Solicitudes de seguidores'),
              ),
            ),
            const SliverToBoxAdapter(child: _SectionTitle('Destacadas')),
            SliverToBoxAdapter(
              child: _NotificationTile(
                highlighted: true,
                avatar: const _LogoAvatar(),
                message: const [
                  _Part('aeroxpert_uas, esteban.pilot', bold: true),
                  _Part(' y otras personas compartieron 4 fotos.'),
                  _Part(' 5 d', muted: true),
                ],
                trailing: const _MediaThumbnail(
                  icon: PhosphorIconsRegular.image,
                  color: Color(0xFF131313),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: _SectionTitle('Últimos 30 días')),
            SliverList.list(children: [
              _NotificationTile(
                avatar: const _InitialAvatar('MG', Color(0xFF8D5A4B)),
                message: const [
                  _Part('meli.giraldom', bold: true),
                  _Part(' comenzó a seguirte.'),
                  _Part(' 13 oct', muted: true),
                ],
                trailing: _ActionButton(
                  label: 'Enviar mensaje',
                  onPressed: () =>
                      _showMessage(context, 'Mensajes próximamente'),
                ),
              ),
              _NotificationTile(
                avatar: const _InitialAvatar('SR', Color(0xFF1176B8)),
                message: const [
                  _Part('superperritosalrescate', bold: true),
                  _Part(' también te empezó a seguir automáticamente.'),
                  _Part(' 7 oct', muted: true),
                ],
                trailing: const _ActionButton(label: 'Siguiendo'),
              ),
              _NotificationTile(
                avatar: const _InitialAvatar('AB', Color(0xFFCA7F68)),
                message: const [
                  _Part('alejandrabtte2', bold: true),
                  _Part(' también te empezó a seguir automáticamente.'),
                  _Part(' 5 oct', muted: true),
                ],
                trailing: const _ActionButton(label: 'Siguiendo'),
              ),
              _NotificationTile(
                avatar: const _InitialAvatar('AB', Color(0xFFCA7F68)),
                message: const [
                  _Part('alejandrabtte2', bold: true),
                  _Part(' aceptó tu solicitud.'),
                  _Part(' 5 oct', muted: true),
                ],
                trailing: _ActionButton(
                  label: 'Enviar mensaje',
                  onPressed: () =>
                      _showMessage(context, 'Mensajes próximamente'),
                ),
              ),
            ]),
            const SliverToBoxAdapter(child: _SectionTitle('Anteriores')),
            SliverList.list(children: const [
              _NotificationTile(
                avatar: _InitialAvatar('LF', Color(0xFF222B3C)),
                message: [
                  _Part('lokilloflorez', bold: true),
                  _Part(' compartió un reel nuevo recientemente.'),
                  _Part(' 18 sept', muted: true),
                ],
                trailing: _MediaThumbnail(
                  icon: PhosphorIconsRegular.play,
                  color: Color(0xFF397B80),
                ),
              ),
              _NotificationTile(
                avatar: _InitialAvatar('PA', Color(0xFF121212)),
                message: [
                  _Part('polari_autos_', bold: true),
                  _Part(
                      ' agregó una historia que no viste: La historia destacada.'),
                  _Part(' 14 sept', muted: true),
                ],
                trailing: _MediaThumbnail(
                  icon: PhosphorIconsRegular.airplaneTilt,
                  color: Color(0xFFB89142),
                ),
              ),
              _NotificationTile(
                avatar: _InitialAvatar('XC', Color(0xFF157CC1)),
                message: [
                  _Part('XpertCommunity', bold: true),
                  _Part(' te da la bienvenida a la comunidad de pilotos UAS.'),
                  _Part(' 1 sept', muted: true),
                ],
              ),
              SizedBox(height: 30),
            ]),
          ],
        ),
      ),
    );
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FollowerRequestsTile extends StatelessWidget {
  const _FollowerRequestsTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 11),
          child: Row(children: [
            const SizedBox(
              width: 56,
              child: Stack(children: [
                _InitialAvatar('UAS', Color(0xFF385C45), size: 42),
                Positioned(
                  left: 23,
                  top: 6,
                  child: _InitialAvatar('14', Color(0xFFC58A91), size: 38),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Solicitudes de seguidores',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    SizedBox(height: 1),
                    Text('pilotos_uas y 14 más',
                        style:
                            TextStyle(fontSize: 13, color: Color(0xFF777777))),
                  ]),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFF566BFF),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(PhosphorIconsRegular.caretRight, size: 20),
          ]),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Text(title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
      );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.avatar,
    required this.message,
    this.trailing,
    this.highlighted = false,
  });

  final Widget avatar;
  final List<_Part> message;
  final Widget? trailing;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: Container(
          color: highlighted ? const Color(0xFFEDF8FE) : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: message
                      .map((part) => TextSpan(
                            text: part.text,
                            style: TextStyle(
                              fontWeight:
                                  part.bold ? FontWeight.w500 : FontWeight.w400,
                              color: part.muted
                                  ? const Color(0xFF777777)
                                  : const Color(0xFF171717),
                            ),
                          ))
                      .toList(),
                ),
                style: const TextStyle(fontSize: 13.5, height: 1.18),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      );
}

class _Part {
  const _Part(this.text, {this.bold = false, this.muted = false});
  final String text;
  final bool bold;
  final bool muted;
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar(this.initials, this.color, {this.size = 46});
  final String initials;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Text(initials,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * .26,
              fontWeight: FontWeight.w700,
            )),
      );
}

class _LogoAvatar extends StatelessWidget {
  const _LogoAvatar();

  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        height: 46,
        padding: const EdgeInsets.all(7),
        decoration: const BoxDecoration(
          color: Color(0xFF159BD7),
          shape: BoxShape.circle,
        ),
        child: Image.asset('assets/images/XpertCommunity.png'),
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onPressed ?? () {},
        style: FilledButton.styleFrom(
          elevation: 0,
          foregroundColor: Colors.black,
          backgroundColor: const Color(0xFFF1F3F6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 78),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
}

class _MediaThumbnail extends StatelessWidget {
  const _MediaThumbnail({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: Colors.white, size: 21),
      );
}
