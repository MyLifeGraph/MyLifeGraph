import 'package:flutter/material.dart';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/theme/app_icons.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/theme/app_visual_tokens.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/daily_capture_controls.dart';

void main() {
  for (final (name, theme) in [
    ('dark', AppTheme.dark),
    ('light', AppTheme.light),
    ('space', AppTheme.space),
  ]) {
    testWidgets('rating hover is neutral, selection and focus stay distinct: $name', (tester) async {
      var value = 8;
      await _pump(tester, StatefulBuilder(builder: (context, setState) =>
        CaptureRatingControl(value: value, semanticPrefix: 'mood',
          onChanged: (next) => setState(() => value = next))), theme: theme);
      final nine = find.widgetWithText(OutlinedButton, '9');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: tester.getCenter(nine));
      await mouse.moveTo(tester.getCenter(nine));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, '8'), findsOneWidget);
      expect(value, 8);
      final style = tester.widget<OutlinedButton>(nine).style!;
      final tokens = theme.extension<AppVisualTokens>()!;
      for (final state in [WidgetState.hovered, WidgetState.focused]) {
        expect(style.backgroundColor!.resolve({state}), Colors.transparent);
        expect(style.overlayColor!.resolve({state})!.withValues(alpha: 1),
          tokens.textPrimary.withValues(alpha: 1));
      }
      expect(style.side!.resolve({WidgetState.focused})!.width, 2);
      await tester.tap(nine);
      await tester.pumpAndSettle();
      expect(value, 9);
      expect(find.widgetWithText(FilledButton, '9'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '8'), findsOneWidget);
    });
  }

  for (final reducedMotion in [false, true]) {
    testWidgets('stress detail expands inside selected card at 320px, reduced motion $reducedMotion', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? selected;
      await _pump(tester, MediaQuery(
        data: MediaQueryData(textScaler: const TextScaler.linear(2), disableAnimations: reducedMotion),
        child: StatefulBuilder(builder: (context, setState) => CaptureChoiceControl<String>(
          value: selected,
          choices: const [CaptureChoice(value: 'work', label: 'Workload', description: 'Workload help'),
            CaptureChoice(value: 'recovery', label: 'Physical recovery')],
          selectedDetail: TextField(controller: controller,
            decoration: const InputDecoration(labelText: 'Specific blocker (optional)')),
          onChanged: (next) => setState(() => selected = next),
        )),
      ), theme: AppTheme.dark);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Workload'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Workload')).selected, isTrue);
      final tokens = AppTheme.dark.extension<AppVisualTokens>()!;
      final selectedFill = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Workload'))
        .color!.resolve({WidgetState.selected});
      expect(selectedFill, Color.alphaBlend(tokens.brand.withValues(alpha: 0.14), tokens.surface));
      expect(tester.widget<Icon>(find.byIcon(AppIcons.expandMore)).color, tokens.textPrimary);
      await tester.tap(find.text('Workload'));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('capture-choice-card-work'));
      expect(find.descendant(of: card, matching: find.byType(TextField)), findsOneWidget);
      final detailBox = tester.widget<DecoratedBox>(find.ancestor(
        of: find.byType(TextField), matching: find.byType(DecoratedBox)).first);
      expect((detailBox.decoration as BoxDecoration).color, tokens.surfaceSubtle);
      expect((detailBox.decoration as BoxDecoration).color, isNot(selectedFill));
      final header = find.widgetWithText(ChoiceChip, 'Workload');
      expect(tester.getSize(card).width, tester.getSize(header).width);
      expect(tester.getSize(find.byType(TextField)).width, tester.getSize(header).width);
      expect(find.descendant(of: card, matching: find.byType(IconButton)), findsNothing);
      await tester.enterText(find.byType(TextField), 'A long day');
      final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Physical recovery'));
      expect(chip.color!.resolve({WidgetState.hovered}), Colors.transparent);
      expect(chip.color!.resolve({WidgetState.focused}), Colors.transparent);
      expect(WidgetStateProperty.resolveAs<BorderSide?>(chip.side, {WidgetState.focused})!.width, 2);
      await tester.ensureVisible(find.text('Physical recovery'));
      await tester.tap(find.text('Physical recovery'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Physical recovery'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: card, matching: find.byType(TextField)), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('capture-choice-card-recovery')),
        matching: find.byType(TextField)), findsOneWidget);
      expect(controller.text, 'A long day');
      await tester.tap(find.text('Physical recovery'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(controller.text, 'A long day');
      expect(selected, 'recovery');
      expect(find.byType(AnimatedSize), reducedMotion ? findsNothing : findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('clock shortcuts wrap midnight and keep the picker', (tester) async {
    String? changed;
    await _pump(tester, CaptureClockControl(
      label: 'Sleep start', semanticLabel: 'estimated sleep start',
      value: '00:15', quickAdjust: true, onChanged: (value) => changed = value,
    ));
    await tester.tap(find.byTooltip('Sleep start 30 minutes earlier'));
    expect(changed, '23:45');
    await tester.tap(find.byTooltip('Sleep start 30 minutes later'));
    expect(changed, '00:45');
    await tester.tap(find.text('00:15'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
  });

  testWidgets('unset clocks do not invent a time through shortcuts', (tester) async {
    await _pump(tester, CaptureClockControl(
      label: 'Sleep start', semanticLabel: 'estimated sleep start',
      value: null, quickAdjust: true, onChanged: (_) => fail('Unexpected change'),
    ));
    expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) =>
        widget is IconButton && widget.tooltip == 'Sleep start 30 minutes earlier'))
        .onPressed, isNull);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((widget) =>
        widget is IconButton && widget.tooltip == 'Sleep start 30 minutes later'))
        .onPressed, isNull);
  });

  testWidgets(
      'Capture information uses a 44px target, dynamic semantics, keyboard, and independent state',
      (tester) async {
    final semantics = tester.ensureSemantics();
    const firstDescription = 'The first hidden Capture explanation.';
    const secondDescription = 'The second hidden Capture explanation.';
    await _pump(
      tester,
      const Column(
        children: [
          CaptureInfoDisclosure(
            heading: 'First Capture section',
            description: firstDescription,
          ),
          CaptureInfoDisclosure(
            heading: 'Second Capture section',
            description: secondDescription,
          ),
        ],
      ),
    );

    final firstTarget = find.byKey(
      const ValueKey('capture-info-control-First Capture section'),
    );
    final firstIcon = find.descendant(
      of: firstTarget,
      matching: find.byIcon(AppIcons.infoOutline),
    );
    expect(find.text(firstDescription), findsNothing);
    expect(find.text(secondDescription), findsNothing);
    expect(find.bySemanticsLabel(firstDescription), findsNothing);
    expect(tester.getSize(firstTarget), const Size.square(44));
    expect(tester.getSize(firstIcon), const Size.square(20));
    final firstSemanticsWidget = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Show information about First Capture section',
      ),
    );
    expect(
      firstSemanticsWidget.container,
      isTrue,
      reason:
          'The information action must remain a separate web semantics node.',
    );
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(
          'Show information about First Capture section',
        ),
      ),
      isSemantics(
        label: 'Show information about First Capture section',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: false,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(firstDescription), findsOneWidget);
    expect(find.text(secondDescription), findsNothing);
    expect(
      tester.getSemantics(
        find.bySemanticsLabel(
          'Hide information about First Capture section',
        ),
      ),
      isSemantics(
        label: 'Hide information about First Capture section',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(firstDescription), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text(firstDescription), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text(firstDescription), findsNothing);

    await tester.tap(
      find.byKey(
        const ValueKey('capture-info-control-Second Capture section'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(firstDescription), findsNothing);
    expect(find.text(secondDescription), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('Capture information changes immediately with Reduced Motion',
      (tester) async {
    const description = 'Reduced-motion Capture information.';
    await _pump(
      tester,
      const CaptureInfoDisclosure(
        heading: 'Reduced motion',
        description: description,
      ),
      disableAnimations: true,
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.descendant(
        of: find.byType(CaptureInfoDisclosure),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcher.duration, Duration.zero);
    await tester.tap(
      find.byKey(
        const ValueKey('capture-info-control-Reduced motion'),
      ),
    );
    await tester.pump();
    expect(find.text(description), findsOneWidget);
  });

  testWidgets('rating control stays compact and omits empty-state cards',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var selected = 0;
    await _pump(
      tester,
      CaptureRatingControl(
        label: 'Mood',
        value: null,
        semanticPrefix: 'evening mood',
        onChanged: (value) => selected = value,
      ),
    );

    expect(find.text('Mood'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Not set'), findsNothing);
    expect(find.text('Choose a value to continue.'), findsNothing);
    expect(
      tester.getSize(
        find
            .ancestor(
              of: find.text('1'),
              matching: find.byType(SizedBox),
            )
            .first,
      ),
      const Size.square(44),
    );

    await tester.tap(find.bySemanticsLabel('evening mood 7 of 10'));
    expect(selected, 7);
    semantics.dispose();
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
