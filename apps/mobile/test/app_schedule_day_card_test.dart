import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_category_visuals.dart';
import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';
import 'package:my_life_graph/core/widgets/app_schedule_day_card.dart';

void main() {
  testWidgets('whole actionable row owns status semantics and hit target',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await _pump(
      tester,
      items: [
        for (final status in AppScheduleItemStatus.values)
          AppScheduleDayItem(
            id: status.name,
            title: status.name,
            detail: '09:00–10:00',
            category: AppCategory.preparation,
            actionable: true,
            status: status,
          ),
      ],
      onTap: (_) => taps += 1,
    );

    for (final (id, label) in const [
      ('notApplicable', 'Completion status not applicable'),
      ('open', 'Not completed'),
      ('completed', 'Completed'),
      ('fullyRated', 'Completed and fully rated'),
    ]) {
      expect(
        tester.getSemantics(
          find.byKey(ValueKey('schedule-day-item-semantics-$id')),
        ),
        isSemantics(
          label: '$id. 09:00–10:00. Preparation. $label.',
          isButton: true,
          hasTapAction: true,
          hasEnabledState: false,
        ),
      );
    }

    await tester.tap(
      find.byKey(const ValueKey('schedule-status-fullyRated')),
    );
    expect(taps, 1, reason: 'The status box belongs to the row action.');
    await tester.tap(find.text('fullyRated'));
    expect(taps, 2);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('schedule-day-item-semantics-fullyRated'),
            ),
          )
          .height,
      greaterThanOrEqualTo(44),
    );
    semantics.dispose();
  });

  testWidgets('rows expose one exact action or static-fact semantics node',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var tappedId = '';
    await _pump(
      tester,
      items: const [
        AppScheduleDayItem(
          id: 'actionable',
          title: 'Algorithms exam',
          detail: '09:00–10:00',
          category: AppCategory.preparation,
          actionable: true,
        ),
        AppScheduleDayItem(
          id: 'static',
          title: 'Algorithms lecture',
          detail: '11:00–12:00',
          category: AppCategory.setup,
          actionable: false,
        ),
      ],
      onTap: (item) => tappedId = item.id,
    );

    const actionableLabel = 'Algorithms exam. 09:00–10:00. Preparation.';
    const staticLabel = 'Algorithms lecture. 11:00–12:00. Setup commitment.';
    expect(find.bySemanticsLabel(actionableLabel), findsOneWidget);
    expect(find.bySemanticsLabel(staticLabel), findsOneWidget);
    expect(
      tester.getSemantics(
        find.byKey(
          const ValueKey('schedule-day-item-semantics-actionable'),
        ),
      ),
      isSemantics(
        label: actionableLabel,
        isButton: true,
        hasTapAction: true,
        hasEnabledState: false,
      ),
    );
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('schedule-day-item-semantics-static')),
      ),
      isSemantics(
        label: staticLabel,
        isButton: false,
        hasTapAction: false,
        hasEnabledState: false,
      ),
    );

    await tester.tap(find.bySemanticsLabel(actionableLabel));
    expect(tappedId, 'actionable');
    semantics.dispose();
  });

  testWidgets('keyboard focus shows a two-pixel ring and Enter activates',
      (tester) async {
    var tappedId = '';
    await _pump(
      tester,
      items: const [
        AppScheduleDayItem(
          id: 'static-first',
          title: 'Static lecture',
          detail: '08:00–09:00',
          category: AppCategory.setup,
          actionable: false,
        ),
        AppScheduleDayItem(
          id: 'keyboard-action',
          title: 'Open preparation',
          detail: '09:00–10:00',
          category: AppCategory.preparation,
          actionable: true,
        ),
      ],
      onTap: (item) => tappedId = item.id,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final focusedMaterial = tester.widget<Material>(
      find.byKey(
        const ValueKey('schedule-day-item-material-keyboard-action'),
      ),
    );
    final focusedShape = focusedMaterial.shape! as RoundedRectangleBorder;
    expect(focusedShape.side.width, 2);
    expect(focusedShape.side.color, AppVisualTokens.light.focus);
    final staticMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('schedule-day-item-material-static-first')),
    );
    expect((staticMaterial.shape! as RoundedRectangleBorder).side.width, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tappedId, 'keyboard-action');
  });

  testWidgets('completed is neutral and fully rated uses category tokens',
      (tester) async {
    for (final theme in [AppTheme.dark, AppTheme.light, AppTheme.space]) {
      await _pump(
        tester,
        theme: theme,
        items: const [
          AppScheduleDayItem(
            id: 'completed',
            title: 'Completed preparation',
            detail: '09:00–10:00',
            category: AppCategory.preparation,
            actionable: false,
            status: AppScheduleItemStatus.completed,
          ),
        ],
      );
      final completedIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('schedule-status-completed')),
          matching: find.byIcon(AppIcons.check),
        ),
      );
      expect(completedIcon.color, theme.colorScheme.onSurfaceVariant);

      await _pump(
        tester,
        theme: theme,
        items: const [
          AppScheduleDayItem(
            id: 'fully-rated',
            title: 'Fully rated preparation',
            detail: '09:00–10:00',
            category: AppCategory.preparation,
            actionable: false,
            status: AppScheduleItemStatus.fullyRated,
          ),
        ],
      );
      final ratedIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('schedule-status-fully-rated')),
          matching: find.byIcon(AppIcons.check),
        ),
      );
      expect(ratedIcon.color, theme.extension<AppVisualTokens>()!.info);
    }
  });

  testWidgets('an item-specific icon preserves source identity',
      (tester) async {
    await _pump(
      tester,
      items: const [
        AppScheduleDayItem(
          id: 'setup',
          title: 'Setup commitment',
          detail: '09:00–10:00',
          category: AppCategory.setup,
          actionable: false,
          icon: AppIcons.settingsSuggestOutlined,
        ),
      ],
    );

    expect(find.byIcon(AppIcons.settingsSuggestOutlined), findsOneWidget);
    expect(find.byIcon(AppIcons.eventRepeatOutlined), findsNothing);
  });

  testWidgets('day rows remain scrollable at 320 pixels and 200 percent text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pump(
      tester,
      textScaler: const TextScaler.linear(2),
      items: const [
        AppScheduleDayItem(
          id: 'narrow',
          title: 'A long preparation title that must wrap safely',
          detail: '09:00–10:00 focus + 15 min recovery · reserved until 10:15',
          category: AppCategory.preparation,
          actionable: true,
          status: AppScheduleItemStatus.fullyRated,
        ),
      ],
    );

    expect(find.textContaining('A long preparation title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required List<AppScheduleDayItem> items,
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  ValueChanged<AppScheduleDayItem>? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AppScheduleDayCard(
            localDate: DateTime(2026, 8, 5),
            items: items,
            emptyLabel: 'Nothing planned.',
            onItemTap: onTap ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
