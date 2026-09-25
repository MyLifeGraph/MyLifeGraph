import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/feedback/app_haptics.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/core/widgets/app_info_disclosure.dart';
import 'package:my_life_graph/features/quick_action/presentation/widgets/daily_capture_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> pulses;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pulses = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') pulses.add(call);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test(
    'default on, no startup pulse, bounded feedback, saved off survives restart',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final container = ProviderContainer();
      final controller = container.read(appHapticsProvider.notifier);
      await controller.selection();
      expect(pulses, isEmpty);
      expect(await container.read(appHapticsProvider.future), isTrue);
      await controller.selection();
      await controller.selection();
      expect(pulses.length, 1);
      expect(pulses.single.arguments, 'HapticFeedbackType.selectionClick');
      expect(await controller.select(false), isTrue);
      container.dispose();

      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      expect(await restored.read(appHapticsProvider.future), isFalse);
      await restored.read(appHapticsProvider.notifier).selection();
      expect(pulses.length, 1);
    },
  );

  test(
    'desktop does not vibrate; unsupported hardware does not throw',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(appHapticsProvider.future);
      final controller = container.read(appHapticsProvider.notifier);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await controller.selection();
      expect(pulses, isEmpty);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async {
            throw PlatformException(code: 'unavailable');
          });
      await expectLater(controller.selection(), completes);
    },
  );

  testWidgets(
    'heading long press opens help; normal info and adjacent actions still work',
    (tester) async {
      var feedback = 0;
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: AppHaptics(
              onSelection: () => feedback++,
              child: Column(
                children: [
                  const AppInfoSectionDisclosure(
                    heading: 'Schedule',
                    description: 'Useful rules.',
                  ),
                  TextButton(
                    onPressed: () => actions++,
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Close'), findsNothing);
      expect(find.text('Useful rules.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Useful rules.')).dy,
        lessThan(tester.getBottomLeft(find.text('Schedule')).dy + 50),
      );
      expect(feedback, 1);
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(find.text('Useful rules.'), findsNothing);
      await tester.tap(find.byTooltip('Show information about Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Useful rules.'), findsOneWidget);
      await tester.tap(find.text('Open'));
      expect(actions, 1);
      expect(feedback, 1);
    },
  );

  testWidgets(
    'rating selection has one pulse and preserves callback; disabled action has none',
    (tester) async {
      var feedback = 0;
      var rating = 8;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: AppHaptics(
              onSelection: () => feedback++,
              child: Builder(
                builder: (context) => StatefulBuilder(
                  builder: (context, setState) => Column(
                    children: [
                      CaptureRatingControl(
                        value: rating,
                        semanticPrefix: 'Energy',
                        onChanged: (value) => setState(() => rating = value),
                      ),
                      TextButton(
                        onPressed: AppHaptics.action(context, null),
                        child: const Text('Disabled'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, '9'));
      await tester.pumpAndSettle();
      expect(rating, 9);
      expect(feedback, 1);
      await tester.tap(find.widgetWithText(FilledButton, '9'));
      await tester.tap(find.text('Disabled'));
      expect(feedback, 1);
    },
  );
}
