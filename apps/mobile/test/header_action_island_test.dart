import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/widgets/app_header_actions.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_page.dart';
import 'support/ui_catalog_capture.dart';

void main() {
  if (captureUiCatalog) setUpAll(loadCatalogFonts);
  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('open island preserves title at $width / $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var calls = 0;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.liquidGlass,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: AppPage(
                  title: 'Planner',
                  compactHeader: true,
                  actions: [
                    AppHeaderActions(
                      pageActions: [
                        IconButton(
                          tooltip: 'Reload',
                          onPressed: () => calls++,
                          icon: const Icon(Icons.refresh),
                        ),
                        IconButton(
                          tooltip: 'Import',
                          onPressed: () {},
                          icon: const Icon(Icons.download),
                        ),
                      ],
                    ),
                  ],
                  children: const [Text('This week')],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('header-island-toggle')),
          findsNothing,
        );
        final title = tester.getRect(find.text('Planner'));
        final surface = tester.getRect(
          find.byKey(const ValueKey('header-action-island')),
        );
        expect(surface.width, lessThanOrEqualTo(180));
        expect(surface.overlaps(title), isFalse);
        await tester.tap(find.byTooltip('Reload'));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(tester.getRect(find.text('Planner')), title);
        expect(
          find.byKey(const ValueKey('header-action-island')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (captureUiCatalog && width == 390 && scale == 1) {
          await captureCatalog(tester, 'island-open-four-slots');
        }
      });
    }
  }
}
