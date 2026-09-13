import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/features/coach/domain/coach_dictation_request.dart';
import 'package:my_life_graph/features/coach/presentation/providers/coach_providers.dart';
import 'package:my_life_graph/features/coach/presentation/widgets/coach_dictation_button.dart';

void main() {
  test(
    'dictation consent resets on logout and account changes without a route listener',
    () async {
      final profile = StateProvider<String?>((ref) => 'profile-a');
      final container = ProviderContainer(
        overrides: [
          coachActiveProfileIdProvider.overrideWith(
            (ref) => ref.watch(profile),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(coachDictationConsentProvider), isFalse);
      container.read(coachDictationConsentProvider.notifier).state = true;
      await container.pump();
      expect(container.read(coachDictationConsentProvider), isTrue);
      container.read(profile.notifier).state = null;
      await container.pump();
      container.read(profile.notifier).state = 'profile-a';
      await container.pump();
      expect(container.read(coachDictationConsentProvider), isFalse);
      container.read(coachDictationConsentProvider.notifier).state = true;
      container.read(profile.notifier).state = 'profile-b';
      await container.pump();
      expect(container.read(coachDictationConsentProvider), isFalse);
    },
  );

  testWidgets(
    'confirmed disclosure is reused on the next recording and route visit',
    (tester) async {
      final originalPlatform = RecordPlatform.instance;
      RecordPlatform.instance = _RecordingPlatform();
      addTearDown(() => RecordPlatform.instance = originalPlatform);
      final container = ProviderContainer(
        overrides: [
          coachActiveProfileIdProvider.overrideWithValue('profile-a'),
        ],
      );
      addTearDown(container.dispose);
      Widget screen() => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: CoachDictationButton(
              enabled: true,
              onText: (_, _) {},
              onBusyChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(screen());
      await tester.tap(find.byTooltip('Dictate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(container.read(coachDictationConsentProvider), isFalse);
      await tester.tap(find.byTooltip('Dictate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      expect(find.text('30s'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Discard recording'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Dictate'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('30s'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      RecordPlatform.instance = _RecordingPlatform();
      await tester.pumpWidget(screen());
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Dictate'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('30s'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    },
  );

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'voice levels, countdown and automatic draft-only stop (reduced motion: $reducedMotion)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final originalPlatform = RecordPlatform.instance;
        final platform = _RecordingPlatform();
        RecordPlatform.instance = platform;
        addTearDown(() => RecordPlatform.instance = originalPlatform);
        final request = _PendingDictation();
        final deliveries = <(String, bool)>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              coachActiveProfileIdProvider.overrideWithValue('profile-a'),
              coachAccessTokenProvider.overrideWithValue(() => 'test-token'),
              coachDictationRequestFactoryProvider.overrideWithValue(
                () => request,
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: reducedMotion,
                  textScaler: const TextScaler.linear(2),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: CoachDictationButton(
                  enabled: true,
                  canSendDirect: true,
                  onText: (text, send) => deliveries.add((text, send)),
                  onBusyChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Dictate'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Record'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const ValueKey('coach-wave-11'))).height,
          4,
        );
        final pcm = Uint8List(3200);
        final samples = ByteData.sublistView(pcm);
        for (var i = 0; i < pcm.length; i += 2) {
          samples.setInt16(
            i,
            328,
            Endian.little,
          ); // About -40 dBFS, not loud test audio.
        }
        platform.audio.add(pcm);
        await tester.pump();
        await tester.pump(); // Rebuild after the asynchronous PCM stream event.
        final bar = tester.widget<AnimatedContainer>(
          find.byKey(const ValueKey('coach-wave-11')),
        );
        expect(bar.constraints!.maxHeight, inExclusiveRange(12, 13));
        expect(
          bar.duration,
          reducedMotion ? Duration.zero : const Duration(milliseconds: 100),
        );
        await tester.pump(const Duration(milliseconds: 150));
        expect(
          tester.getSize(find.byKey(const ValueKey('coach-wave-11'))).height,
          inExclusiveRange(12, 13),
        );
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('25s'), findsOneWidget);
        expect(request.calls, 0);
        await tester.pump(const Duration(seconds: 25));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        expect(request.calls, 1);
        expect(find.byKey(const Key('coach-dictation-waveform')), findsNothing);
        request.result.complete('Recognized question');
        await tester.pumpAndSettle();
        expect(deliveries, [('Recognized question', false)]);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox());
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
      },
    );
  }

  for (final action in ['stop', 'send', 'cancel', 'profile']) {
    testWidgets('dictation preserves delivery and cancellation for $action', (
      tester,
    ) async {
      final originalPlatform = RecordPlatform.instance;
      final platform = _RecordingPlatform();
      RecordPlatform.instance = platform;
      addTearDown(() => RecordPlatform.instance = originalPlatform);
      final profile = StateProvider<String?>((ref) => 'profile-a');
      final request = _PendingDictation();
      final deliveries = <(String, bool)>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coachActiveProfileIdProvider.overrideWith(
              (ref) => ref.watch(profile),
            ),
            coachAccessTokenProvider.overrideWithValue(() => 'test-token'),
            coachDictationRequestFactoryProvider.overrideWithValue(
              () => request,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CoachDictationButton(
                enabled: true,
                canSendDirect: true,
                onText: (text, send) => deliveries.add((text, send)),
                onBusyChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Dictate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      platform.audio.add(Uint8List(3200));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(
            Key('coach-dictation-${action == 'send' ? 'send' : 'stop'}'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      expect(request.calls, 1);
      expect(request.token, 'test-token');
      await tester.runAsync(() async {
        if (action == 'cancel') {
          await tester.tap(find.byKey(const Key('coach-dictation-discard')));
        } else if (action == 'profile') {
          ProviderScope.containerOf(
            tester.element(find.byType(CoachDictationButton)),
          ).read(profile.notifier).state = 'profile-b';
          await tester.pump();
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      request.result.complete('Recognized question');
      await tester.pumpAndSettle();
      if (action == 'cancel' || action == 'profile') {
        expect(request.cancelled, isTrue);
        expect(deliveries, isEmpty);
      } else {
        expect(deliveries, [('Recognized question', action == 'send')]);
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
    });
  }
  for (final action in ['discard', 'stop', 'send']) {
    testWidgets('recording bar replaces input and handles $action', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final originalPlatform = RecordPlatform.instance;
      final platform = _RecordingPlatform();
      RecordPlatform.instance = platform;
      addTearDown(() {
        RecordPlatform.instance = originalPlatform;
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coachActiveProfileIdProvider.overrideWithValue('profile-a'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: CoachDictationButton(
                  enabled: true,
                  canSendDirect: action == 'send',
                  onText: (_, _) =>
                      fail('Empty recording must not produce text'),
                  onBusyChanged: (_) {},
                  idleBuilder: (microphone) => Row(
                    children: [
                      const Expanded(child: Text('Existing draft')),
                      microphone,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Dictate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      expect(find.text('Existing draft'), findsNothing);
      expect(find.text('30s'), findsOneWidget);
      final send = tester.widget<IconButton>(
        find.byKey(const Key('coach-dictation-send')),
      );
      expect(send.onPressed != null, action == 'send');
      final discardX = tester
          .getCenter(find.byKey(const Key('coach-dictation-discard')))
          .dx;
      final stopX = tester
          .getCenter(find.byKey(const Key('coach-dictation-stop')))
          .dx;
      final sendX = tester
          .getCenter(find.byKey(const Key('coach-dictation-send')))
          .dx;
      expect(discardX, lessThan(stopX));
      expect(stopX, lessThan(sendX));
      await tester.runAsync(() async {
        await tester.tap(find.byKey(Key('coach-dictation-$action')));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(platform.calls, contains(action == 'discard' ? 'cancel' : 'stop'));
      expect(find.text('Existing draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
    });
  }
  test('standalone dictation is restricted to signed-in real development', () {
    for (final environment in [
      'development',
      'staging',
      'pilot',
      'production',
    ]) {
      for (final mock in [false, true]) {
        for (final profile in ['profile-a', null]) {
          final container = ProviderContainer(
            overrides: [
              appConfigProvider.overrideWithValue(
                AppConfig(
                  environment: environment,
                  supabaseUrl: '',
                  aiServiceBaseUrl: '',
                  useMockData: mock,
                ),
              ),
              coachActiveProfileIdProvider.overrideWithValue(profile),
            ],
          );
          expect(
            container.read(coachLocalDictationProvider),
            environment == 'development' && !mock && profile != null,
          );
          container.dispose();
        }
      }
    }
  });
  testWidgets('guest cannot start recording or upload', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [coachActiveProfileIdProvider.overrideWithValue(null)],
        child: MaterialApp(
          home: Scaffold(
            body: CoachDictationButton(
              enabled: true,
              onText: (_, _) => fail('Unexpected text'),
              onBusyChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
  });

  testWidgets(
    'audio disclosure precedes permission and cancel preserves draft',
    (tester) async {
      var busy = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            coachActiveProfileIdProvider.overrideWithValue('profile-a'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CoachDictationButton(
                enabled: true,
                onText: (_, _) => fail('Unexpected text'),
                onBusyChanged: (value) => busy = value,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Dictate'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Audio is sent to the MyLifeGraph server'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(busy, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

class _PendingDictation implements CoachDictationRequest {
  final result = Completer<String?>();
  var calls = 0;
  var cancelled = false;
  String? token;

  @override
  Future<String?> transcribe(Uint8List pcm, {required String accessToken}) {
    expect(pcm.length, 3200);
    calls++;
    token = accessToken;
    return result.future;
  }

  @override
  void cancel() => cancelled = true;
}

class _RecordingPlatform extends RecordPlatform {
  final calls = <String>[];
  final audio = StreamController<Uint8List>.broadcast();
  @override
  Future<void> create(String recorderId) async {}
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;
  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async => audio.stream;
  @override
  Future<String?> stop(String recorderId) async {
    calls.add('stop');
    return null;
  }

  @override
  Future<void> cancel(String recorderId) async {
    calls.add('cancel');
  }

  @override
  Future<void> dispose(String recorderId) async {
    await audio.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
