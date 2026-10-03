import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/features/focus_protection/presentation/widgets/blocking_screen_preview.dart';

void main() {
  testWidgets(
    'vertical drag across real Android preview scrolls its parent, taps stay native',
    (tester) async {
      final platformMethods = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        platformMethods.add(call.method);
        if (call.method == 'create') return 0;
        if (call.method == 'resize') {
          final args = call.arguments as Map;
          return {'width': args['width'], 'height': args['height']};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 420,
              child: ListView(
                controller: controller,
                children: const [
                  SizedBox(
                    height: 560,
                    child: BlockingScreenPreview(custom: {}, counters: {}),
                  ),
                  SizedBox(height: 64, child: Text('Editor action')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Exercise the actual AndroidView/gesture arena, not a substitute
      // GestureDetector and not an ensureVisible/programmatic scroll.
      await tester.dragFrom(const Offset(160, 280), const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(150));
      expect(find.text('Editor action').hitTestable(), findsOneWidget);
      platformMethods.clear();
      await tester.tapAt(const Offset(160, 100));
      await tester.pump();
      expect(platformMethods, contains('touch'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'non-Android host explicitly marks native preview unavailable',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BlockingScreenPreview(custom: {}, counters: {}),
          ),
        ),
      );
      expect(find.byType(AndroidView), findsNothing);
      expect(
        find.text('Native preview is available on Android.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'Android creates only the native preview surface',
    (tester) async {
      final platformMethods = <String>[];
      var productCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        platformMethods.add(call.method);
        if (call.method == 'create') return 0;
        if (call.method == 'resize') {
          final args = call.arguments as Map;
          return {'width': args['width'], 'height': args['height']};
        }
        return null;
      });
      const productChannel = MethodChannel('com.mylifegraph.app/blocking_v2');
      messenger.setMockMethodCallHandler(productChannel, (_) async {
        productCalls++;
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        messenger.setMockMethodCallHandler(productChannel, null);
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 480,
              child: BlockingScreenPreview(
                custom: {'waitSeconds': 15, 'tone': 'glass'},
                counters: {'today': 2, 'total': 4},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final view = tester.widget<AndroidView>(find.byType(AndroidView));
      expect(view.viewType, BlockingScreenPreview.viewType);
      expect(view.creationParams, {
        'custom': {'waitSeconds': 15, 'tone': 'glass'},
        'counters': {'today': 2, 'total': 4},
        'strictLocked': false,
      });
      expect(platformMethods, contains('create'));
      expect(productCalls, 0);
      expect(tester.takeException(), isNull);
      final identities = <Key?>{};
      // Creation parameters are immutable: every saved icon/background change
      // must replace the native surface rather than retain an old screen.
      for (final tone in ['glass', 'dark', 'light', 'space']) {
        for (final icon in [
          'shield',
          'work',
          'games',
          'social',
          'sleep',
          'study',
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 320,
                  height: 480,
                  child: BlockingScreenPreview(
                    custom: {'waitSeconds': 3, 'tone': tone, 'icon': icon},
                    counters: const {'today': 2, 'total': 4},
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          final changed = tester.widget<AndroidView>(find.byType(AndroidView));
          expect(identities.add(changed.key), isTrue);
          expect((changed.creationParams as Map)['custom'], {
            'waitSeconds': 3,
            'tone': tone,
            'icon': icon,
          });
          expect(productCalls, 0);
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('preview passes saved values without modifying counters', (
    tester,
  ) async {
    final custom = <String, Object?>{
      'title': 'A deliberate pause',
      'message': 'Choose your next step.',
      'icon': 'study',
      'tone': 'light',
      'waitSeconds': 900,
    };
    final counters = <String, Object?>{'today': 3, 'total': 9};
    Map<String, Object?>? received;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockingScreenPreview(
            custom: custom,
            counters: counters,
            strictLocked: true,
            platformViewBuilder: (_, parameters) {
              received = parameters;
              return const Text('Native view test double');
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(received, {
      'custom': custom,
      'counters': counters,
      'strictLocked': true,
    });
    expect(custom['waitSeconds'], 900);
    expect(counters, {'today': 3, 'total': 9});
    expect(find.text('Native view test double'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
