import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_feature_palette.dart';

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
    final theme = AppTheme.resolve(switch (custom['tone']) {
      'light' => AppThemeId.light,
      'dark' => AppThemeId.dark,
      'space' => AppThemeId.space,
      _ => AppThemeId.liquidGlass,
    });
    final accent = switch (custom['accent']) {
      'mint' => AppFeaturePalette.mint,
      'blue' => AppFeaturePalette.blue,
      'violet' => AppFeaturePalette.violet,
      'rose' => AppFeaturePalette.rose,
      _ => theme.colorScheme.primary,
    };
    final spacing = switch (custom['layout']) {
      'compact' => 8.0,
      'spacious' => 24.0,
      _ => 16.0,
    };
    final icon = switch (custom['icon']) {
      'work' => AppIcons.briefcaseOutlined,
      'games' => AppIcons.gameController,
      'social' => AppIcons.forumOutlined,
      'sleep' => AppIcons.bedtimeOutlined,
      'study' => AppIcons.schoolOutlined,
      _ => AppIcons.shieldOutlined,
    };
    return Theme(
      data: theme,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Web preview · Native on Android',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: spacing * 2),
                    Icon(icon, size: 48, color: accent),
                    SizedBox(height: spacing),
                    Text(
                      custom['title'] as String? ?? 'Stay focused',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    SizedBox(height: spacing),
                    Text(
                      custom['message'] as String? ??
                          'Take a breath. Choose your next step.',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: spacing),
                    if (strictLocked) const Text('Strict mode'),
                    SizedBox(height: spacing),
                    OutlinedButton(
                      onPressed: null,
                      child: Text(
                        (custom['waitSeconds'] as int? ?? 0) == 0
                            ? 'Return to MyLifeGraph'
                            : 'Return in ${custom['waitSeconds']}s',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
    custom['accent'],
    custom['layout'],
    custom['waitSeconds'],
    counters['today'],
    counters['total'],
    counters['attemptsToday'],
    counters['attemptsTotal'],
    locked,
  ].map((value) => '${'$value'.length}:$value').join('|');
}
