import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_surface.dart';
import 'package:my_life_graph/features/coach/domain/coach.dart';
import 'package:my_life_graph/features/coach/presentation/widgets/coach_uncertainty_view.dart';

void main() {
  const levels = [
    ('low', 'Low uncertainty', AppIcons.infoOutline, AppStatusTone.success),
    (
      'medium',
      'Medium uncertainty',
      AppIcons.warningAmberOutlined,
      AppStatusTone.attention,
    ),
    ('high', 'High uncertainty', AppIcons.errorOutline, AppStatusTone.danger),
  ];
  for (final themeId in AppThemeId.values) {
    for (final scale in [1.0, 2.0]) {
      for (final (level, label, icon, tone) in levels) {
        testWidgets('$level remains explicit at $scale text in $themeId', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          const reason =
              'Only four completed sessions were recorded. '
              'Missing days limit what this answer can explain.';
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.resolve(themeId),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(32),
                    child: CoachUncertaintyView(
                      uncertainty: CoachUncertainty(
                        level: level,
                        reason: reason,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.text(label), findsOneWidget);
          expect(find.text(reason), findsOneWidget);
          expect(find.byIcon(icon), findsOneWidget);
          expect(
            tester.widget<AppStatusPill>(find.byType(AppStatusPill)).tone,
            tone,
          );
          expect(find.bySemanticsLabel(RegExp(label)), findsWidgets);
            expect(tester.takeException(), isNull);
            semantics.dispose();
        });
      }
    }
  }
}
