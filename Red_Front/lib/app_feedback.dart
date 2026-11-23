import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:toastification/toastification.dart';

enum FeedbackKind { success, error, info, warning }

abstract final class AppFeedback {
  static void show(
    String message, {
    FeedbackKind kind = FeedbackKind.info,
    String? title,
  }) {
    final isError = kind == FeedbackKind.error;
    final icon = switch (kind) {
      FeedbackKind.success => PhosphorIconsRegular.checkCircle,
      FeedbackKind.error => PhosphorIconsRegular.warningCircle,
      FeedbackKind.warning => PhosphorIconsRegular.warning,
      FeedbackKind.info => PhosphorIconsRegular.info,
    };

    toastification.showCustom(
      alignment: Alignment.center,
      autoCloseDuration: const Duration(milliseconds: 2600),
      animationDuration: const Duration(milliseconds: 220),
      animationBuilder: (context, animation, alignment, child) {
        final slide = Tween<Offset>(
          begin: const Offset(0, -.28),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      builder: (context, item) => SizedBox(
        width: double.infinity,
        child: Center(
          child: GestureDetector(
            onTap: () => toastification.dismiss(item),
            child: Container(
              width: (MediaQuery.sizeOf(context).width - 44)
                  .clamp(0, 340)
                  .toDouble(),
              margin: const EdgeInsets.symmetric(horizontal: 22),
              padding: const EdgeInsets.fromLTRB(10, 9, 16, 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F1F1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E2E2)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 22,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isError ? const Color(0xFFFFE4E2) : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 19,
                    color: isError ? const Color(0xFFC9342C) : Colors.black,
                  ),
                ),
                const SizedBox(width: 11),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null) ...[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF111111),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF555555),
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  static void success(String message, {String? title}) =>
      show(message, kind: FeedbackKind.success, title: title);

  static void error(String message, {String? title}) =>
      show(message, kind: FeedbackKind.error, title: title);

  static void info(String message, {String? title}) =>
      show(message, kind: FeedbackKind.info, title: title);

  static Future<bool> confirmDelete(
    BuildContext context, {
    required String itemName,
  }) async {
    final isLogout = itemName == 'la sesión';
    final destructiveColor =
        isLogout ? const Color(0xFF171717) : const Color(0xFFD93F38);
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x66000000),
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
            const SizedBox(height: 20),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isLogout
                      ? const Color(0xFFF0F0F0)
                      : const Color(0xFFFFEDEC),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  isLogout
                      ? PhosphorIconsRegular.signOut
                      : PhosphorIconsRegular.trash,
                  size: 21,
                  color: destructiveColor,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLogout ? 'Cerrar sesión' : 'Eliminar $itemName',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      isLogout
                          ? 'Tendrás que ingresar nuevamente para volver a tu cuenta.'
                          : 'Esta acción es permanente y no se puede deshacer.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFF6F6F6F),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                style: FilledButton.styleFrom(
                  elevation: 0,
                  backgroundColor: destructiveColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(isLogout ? 'Cerrar sesión' : 'Eliminar'),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF333333),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                child: const Text('Cancelar'),
              ),
            ),
          ]),
        ),
      ),
    );
    return result ?? false;
  }
}
