import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/preferences/assistant_language.dart';

class AssistantLanguageButton extends ConsumerWidget {
  const AssistantLanguageButton({
    required this.scope,
    this.enabled = true,
    super.key,
  });
  final String scope;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(assistantLanguageProvider(scope));
    final german = language.value == 'de';
    return IconButton(
      key: Key('$scope-language-toggle'),
      tooltip: german
          ? 'Deutsch · Switch to English'
          : 'English · Zu Deutsch wechseln',
      onPressed: !enabled || language.loading
          ? null
          : () async {
              final saved = await language.toggle();
              if (!saved && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Language could not be saved. Try again.'),
                  ),
                );
              }
            },
      // Windows does not reliably render country-flag emoji. Paint these tiny
      // flags so the same indicator appears on web and Android without fonts.
      icon: CustomPaint(
        key: Key(german ? 'language-flag-de' : 'language-flag-en'),
        size: const Size(24, 16),
        painter: _LanguageFlag(german),
      ),
    );
  }
}

class _LanguageFlag extends CustomPainter {
  const _LanguageFlag(this.german);
  final bool german;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
    );
    final paint = Paint();
    if (german) {
      const colors = [Color(0xff171717), Color(0xffdd0000), Color(0xffffce00)];
      for (var i = 0; i < 3; i++) {
        canvas.drawRect(
          Rect.fromLTWH(0, i * size.height / 3, size.width, size.height / 3),
          paint..color = colors[i],
        );
      }
    } else {
      canvas.drawRect(
        Offset.zero & size,
        paint..color = const Color(0xff012169),
      );
      for (final color in [const Color(0xffffffff), const Color(0xffc8102e)]) {
        paint
          ..color = color
          ..strokeWidth = color == const Color(0xffffffff) ? 4 : 1.5;
        canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
        canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
        paint.strokeWidth = color == const Color(0xffffffff) ? 6 : 3;
        canvas.drawLine(
          Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height),
          paint,
        );
        canvas.drawLine(
          Offset(0, size.height / 2),
          Offset(size.width, size.height / 2),
          paint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LanguageFlag oldDelegate) => german != oldDelegate.german;
}
