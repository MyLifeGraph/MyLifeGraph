import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/navigation/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_theme_selection_provider.dart';
import 'core/widgets/app_backdrop.dart';
import 'core/widgets/offline_status_banner.dart';

class PersonalOptimizationApp extends ConsumerWidget {
  const PersonalOptimizationApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeSelection = ref.watch(appThemeSelectionProvider);

    return MaterialApp.router(
      title: 'MyLifeGraph',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.resolve(themeSelection),
      routerConfig: router,
      builder: (context, child) {
        final content = AppBackdrop(
          child: OfflineStatusBanner(
            child: child ?? const SizedBox.shrink(),
          ),
        );
        final highContrast = MediaQuery.highContrastOf(context);
        final disableAnimations = MediaQuery.disableAnimationsOf(context);
        if (!highContrast && !disableAnimations) return content;
        final resolvedTheme = highContrast
            ? AppTheme.resolve(themeSelection, highContrast: true)
            : Theme.of(context);
        return Theme(
          data: disableAnimations
              ? AppTheme.withoutAnimations(resolvedTheme)
              : resolvedTheme,
          child: content,
        );
      },
    );
  }
}
