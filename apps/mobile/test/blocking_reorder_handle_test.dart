import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/feedback/app_haptics.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/blocking_reorder_handle.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _open(
  WidgetTester tester, {
  required VoidCallback onFeedback,
  required void Function(int, int) onReorder,
  ScrollController? scrollController,
  bool enabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppHaptics(
          onSelection: onFeedback,
          child: ListView(
            controller: scrollController,
            children: [
              const SizedBox(height: 80),
              ReorderableListView.builder(
                shrinkWrap: true,
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: 3,
                onReorderItem: onReorder,
                itemBuilder: (_, index) => SizedBox(
                  key: ValueKey(index),
                  height: 100,
                  child: Row(
                    children: [
                      Expanded(child: Text('Plan $index')),
                      BlockingReorderHandle(
                        index: index,
                        enabled: enabled,
                        child: SizedBox(
                          key: ValueKey('handle-$index'),
                          width: 44,
                          height: 44,
                          child: const ColoredBox(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('500ms hold arms one pulse and real nested-list reorder', (
    tester,
  ) async {
    var feedback = 0;
    final reorders = <(int, int)>[];
    await _open(
      tester,
      onFeedback: () => feedback++,
      onReorder: (oldIndex, newIndex) => reorders.add((oldIndex, newIndex)),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('handle-0'))),
    );
    await tester.pump(const Duration(milliseconds: 499));
    expect(feedback, 0);
    expect(reorders, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(feedback, 1);
    await gesture.moveBy(const Offset(0, 100));
    await tester.pumpAndSettle();
    await gesture.moveBy(const Offset(0, 300));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(reorders, [(0, 2)]);
    expect(feedback, 1);
  });

  testWidgets('early release and cancellation never arm or vibrate', (
    tester,
  ) async {
    var feedback = 0;
    var reorders = 0;
    await _open(
      tester,
      onFeedback: () => feedback++,
      onReorder: (_, _) => reorders++,
    );
    final handle = find.byKey(const ValueKey('handle-0'));
    final short = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 400));
    await short.up();
    await tester.pumpAndSettle();
    final cancelled = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 400));
    await cancelled.cancel();
    await tester.pump(const Duration(seconds: 1));
    expect(feedback, 0);
    expect(reorders, 0);
  });

  testWidgets('early handle swipe scrolls outer list without reordering', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var feedback = 0;
    var reorders = 0;
    await _open(
      tester,
      scrollController: controller,
      onFeedback: () => feedback++,
      onReorder: (_, _) => reorders++,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('handle-2'))),
    );
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(feedback, 0);
    expect(reorders, 0);
  });

  testWidgets('disabled handle ignores long hold', (tester) async {
    var feedback = 0;
    var reorders = 0;
    await _open(
      tester,
      enabled: false,
      onFeedback: () => feedback++,
      onReorder: (_, _) => reorders++,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('handle-0'))),
    );
    await tester.pump(const Duration(seconds: 2));
    await gesture.moveBy(const Offset(0, 210));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(feedback, 0);
    expect(reorders, 0);
  });

  for (final hapticsEnabled in [true, false]) {
    testWidgets('drag respects saved haptic preference $hapticsEnabled', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        AppHapticsController.preferenceKey: hapticsEnabled,
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var pulses = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') pulses++;
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(appHapticsProvider.future);
      var reorders = 0;
      await _open(
        tester,
        onFeedback: () =>
            container.read(appHapticsProvider.notifier).selection(),
        onReorder: (_, _) => reorders++,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('handle-0'))),
      );
      await tester.pump(const Duration(seconds: 1));
      await gesture.moveBy(const Offset(0, 210));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(reorders, 1);
      expect(pulses, hapticsEnabled ? 1 : 0);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
