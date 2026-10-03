import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_spacing.dart';

typedef BlockingPreviewViewBuilder =
    Widget Function(BuildContext context, Map<String, Object?> parameters);

/// Read-only native preview. Its timer belongs to the platform view and no
/// product methods, saved rules or attempt counters are written by this widget.
class BlockingScreenPreview extends StatelessWidget {
  const BlockingScreenPreview({
    super.key,
    required this.custom,
    required this.counters,
    this.strictLocked = false,
    this.platformViewBuilder,
  });

  final Map<String, Object?> custom;
  final Map<String, Object?> counters;
  final bool strictLocked;

  /// Allows widget tests to inspect the creation parameters without creating an
  /// Android surface. Production callers use the actual host platform below.
  final BlockingPreviewViewBuilder? platformViewBuilder;

  static const viewType = 'com.mylifegraph.app/blocking_preview';

  @override
  Widget build(BuildContext context) {
    final parameters = <String, Object?>{
      'custom': custom,
      'counters': counters,
      'strictLocked': strictLocked,
    };
    final builder = platformViewBuilder;
    if (builder != null) return builder(context, parameters);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        key: ValueKey(_previewIdentity(custom, counters, strictLocked)),
        viewType: viewType,
        creationParams: parameters,
        creationParamsCodec: const StandardMessageCodec(),
        // Keep native Return taps, but yield vertical drags to the surrounding
        // Customize page. An eager recognizer traps users inside this tall
        // platform surface, leaving the editor below it unreachable on phones.
        gestureRecognizers: {
          Factory<TapGestureRecognizer>(TapGestureRecognizer.new),
        },
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'Native preview is available on Android.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  // Platform creation parameters are immutable. Recreate after an appearance
  // edit so a retained view cannot silently display the previous saved values.
  static String _previewIdentity(
    Map<String, Object?> custom,
    Map<String, Object?> counters,
    bool locked,
  ) => [
    custom['title'],
    custom['message'],
    custom['icon'],
    custom['tone'],
    custom['waitSeconds'],
    counters['today'],
    counters['total'],
    counters['attemptsToday'],
    counters['attemptsTotal'],
    locked,
  ].map((value) => '${'$value'.length}:$value').join('|');
}
