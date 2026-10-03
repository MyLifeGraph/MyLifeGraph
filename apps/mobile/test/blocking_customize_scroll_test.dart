import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/features/app_updates/application/app_updates.dart';
import 'package:my_life_graph/features/focus_protection/application/blocking_gateway.dart';
import 'package:my_life_graph/features/focus_protection/application/focus_protection_gateway.dart';
import 'package:my_life_graph/features/focus_protection/domain/focus_protection.dart';
import 'package:my_life_graph/features/focus_protection/presentation/pages/blocking_page.dart';
import 'package:my_life_graph/features/shell/presentation/main_shell.dart';

import 'blocking_plans_test.dart' show FakeBlockingGateway;
import 'support/native_blocking_preview.dart';
import 'support/ui_catalog_capture.dart';

class _AndroidGateway extends UnsupportedFocusProtectionGateway {
  @override
  Future<FocusProtectionStatus> readStatus() async {
    final status = await super.readStatus();
    return FocusProtectionStatus(
      platformSupported: true,
      accessibilityEnabled: true,
      notificationPolicyGranted: false,
      lease: null,
      configuration: status.configuration.copyWith(
        enabled: true,
        blockSelectedApps: true,
      ),
    );
  }
}

void main() {
  setUpAll(loadCatalogFonts);
  for (final (themeName, theme) in [
    ('glass', AppTheme.liquidGlass),
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
    ('space', AppTheme.space),
  ]) {
    for (final (width, scale) in [(360.0, 1.0), (320.0, 2.0)]) {
      testWidgets(
        'native Customize scroll/edit/reopen/Back $themeName $width/$scale',
        (tester) async {
          stubNativeBlockingPreview();
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 640);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          addTearDown(() {
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform_views, null);
          });
          final gateway = FakeBlockingGateway();
          final router = GoRouter(
            initialLocation: '/test-launcher',
            routes: [
              GoRoute(
                path: '/test-launcher',
                builder: (context, _) => Scaffold(
                  body: TextButton(
                    onPressed: () => context.push(AppRoutes.focusProtection),
                    child: const Text('Open blocking'),
                  ),
                ),
              ),
              GoRoute(
                path: AppRoutes.focusProtection,
                builder: (_, _) => const MainShell(
                  currentPath: AppRoutes.focusProtection,
                  child: BlockingPage(),
                ),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appSurfaceCapabilitiesProvider.overrideWithValue(
                  const AppSurfaceCapabilities(
                    isLocalDemo: false,
                    canUseSyncedHabits: true,
                    canUseSyncedExecution: true,
                    canShowCoachSurface: true,
                  ),
                ),
                appUpdatesSupportedProvider.overrideWithValue(false),
                blockingGatewayProvider.overrideWithValue(gateway),
                focusProtectionGatewayProvider.overrideWithValue(
                  _AndroidGateway(),
                ),
              ],
              child: MaterialApp.router(
                debugShowCheckedModeBanner: false,
                routerConfig: router,
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open blocking'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          expect(
            find.byTooltip('Permissions & limits').hitTestable(),
            findsOneWidget,
          );
          for (final label in ['Strict', 'Insights', 'Plans']) {
            final tab = find.widgetWithText(TextButton, label);
            expect(tab.hitTestable(), findsOneWidget);
            await tester.tap(tab);
            await tester.pumpAndSettle();
          }
          await tester.tap(find.widgetWithText(TextButton, 'Customize'));
          await tester.pumpAndSettle();
          final customize = find.widgetWithText(FilledButton, 'Customize');
          expect(
            customize.hitTestable(),
            findsOneWidget,
            reason:
                '${tester.getRect(customize)}; '
                'list ${tester.getRect(find.byType(ListView))}',
          );
          expect(find.byType(AndroidView), findsOneWidget);
          if (captureUiCatalog && themeName == 'glass') {
            await captureCatalog(
              tester,
              'customize-native-frame-$width-$scale',
            );
          }
          final scroll = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          // Repeat real pointer drags over the AndroidView, not side-gutter
          // swipes or programmatic ensureVisible that masked the original bug.
          for (var attempt = 0; attempt < 3; attempt++) {
            final preview = tester.getRect(find.byType(AndroidView));
            final visiblePreview = preview.intersect(
              tester.getRect(find.byType(ListView)),
            );
            expect(visiblePreview.height, greaterThan(20));
            final start = visiblePreview.center;
            await tester.dragFrom(start, const Offset(0, -150));
            await tester.pumpAndSettle();
            expect(scroll.position.pixels, greaterThan(0));
            await tester.dragFrom(
              tester.getRect(find.byType(ListView)).center,
              const Offset(0, 450),
            );
            await tester.pumpAndSettle();
            expect(customize.hitTestable(), findsOneWidget);
          }
          expect(gateway.saveAttempts, 0);
          await tester.tap(customize);
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          await tester.pumpAndSettle();
          final title = find.byType(TextField).first;
          await tester.enterText(title, 'A deliberate pause');
          // Typing does not touch the native saved customization yet.
          expect(gateway.saveAttempts, 0);
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          final save = find.widgetWithText(FilledButton, 'Save');
          await tester.ensureVisible(save);
          await tester.pumpAndSettle();
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(gateway.custom['title'], 'A deliberate pause');
          final native = tester.widget<AndroidView>(find.byType(AndroidView));
          expect(
            ((native.creationParams as Map)['custom'] as Map)['title'],
            'A deliberate pause',
          );
          await tester.tap(customize);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!
                .text,
            'A deliberate pause',
          );
          await tester.enterText(find.byType(TextField).first, 'Unsaved draft');
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(BlockingPage), findsOneWidget);
          expect(gateway.saveAttempts, 1);
          expect(gateway.custom['title'], 'A deliberate pause');
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('Open blocking'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }
}
