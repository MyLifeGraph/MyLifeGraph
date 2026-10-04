import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_life_graph/composition/widgets/capture_note_field.dart';
import 'package:my_life_graph/features/coach/domain/coach_dictation_request.dart';
import 'package:my_life_graph/features/coach/presentation/providers/coach_providers.dart';
import 'package:my_life_graph/features/coach/presentation/widgets/coach_dictation_button.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final theme in [
    AppTheme.dark,
    AppTheme.light,
    AppTheme.space,
    AppTheme.liquidGlass,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'compact note fits 320px theme ${theme.brightness} scale $scale ${theme.hashCode}',
        (tester) async {
          tester.view.physicalSize = const Size(320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: CaptureNoteField(
                    controller: controller,
                    maxLines: 2,
                    onChanged: (_) {},
                    onBusyChanged: (_) {},
                  ),
                ),
              ),
            ),
          );
          expect(find.byTooltip('Dictate'), findsOneWidget);
          expect(tester.getSize(find.byType(TextField)).height, lessThan(210));
          await tester.enterText(find.byType(TextField), 'A short note.');
          await tester.pump();
          expect(controller.text, 'A short note.');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'note dictation appends reviewed words and rejects overflow without truncation',
    (tester) async {
      final controller = TextEditingController(text: 'My existing note');
      addTearDown(controller.dispose);
      var changes = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CaptureNoteField(
                controller: controller,
                onChanged: (_) => changes++,
                onBusyChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      tester
          .widget<CoachDictationButton>(find.byType(CoachDictationButton))
          .onText('  Extra context  ', false);
      await tester.pump();
      expect(controller.text, 'My existing note\nExtra context');
      expect(changes, 1);
      controller.text = 'x' * 495;
      tester
          .widget<CoachDictationButton>(find.byType(CoachDictationButton))
          .onText('Too long', false);
      await tester.pump();
      expect(controller.text, 'x' * 495);
      expect(changes, 1);
      expect(find.textContaining('Recording not added.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final cancel in [false, true]) {
    testWidgets(
      'note recorder survives busy rebuild; cancelled=$cancel never overwrites text',
      (tester) async {
        final originalPlatform = RecordPlatform.instance;
        final platform = _Recorder();
        RecordPlatform.instance = platform;
        addTearDown(() => RecordPlatform.instance = originalPlatform);
        final request = _Dictation();
        final controller = TextEditingController(text: 'Original');
        addTearDown(controller.dispose);
        final busyValues = <bool>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              coachActiveProfileIdProvider.overrideWithValue('note-owner'),
              coachAccessTokenProvider.overrideWithValue(
                () => 'synthetic-token',
              ),
              coachDictationRequestFactoryProvider.overrideWithValue(
                () => request,
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: CaptureNoteField(
                  controller: controller,
                  onChanged: (_) {},
                  onBusyChanged: busyValues.add,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Dictate'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Record'));
        await tester.pumpAndSettle();
        expect(find.text('30s'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
        platform.audio.add(Uint8List(3200));
        await tester.pump();
        await tester.pump();
        await tester.runAsync(() async {
          await tester.tap(find.byTooltip('Stop and review'));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        expect(request.calls, 1);
        if (cancel) {
          await tester.runAsync(() async {
            await tester.tap(find.byTooltip('Discard recording'));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
          await tester.pump();
        }
        request.result.complete('Spoken note');
        await tester.pumpAndSettle();
        expect(controller.text, cancel ? 'Original' : 'Original\nSpoken note');
        expect(busyValues.last, isFalse);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox());
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
      },
    );
  }
}

class _Dictation implements CoachDictationRequest {
  final result = Completer<String?>();
  int calls = 0;
  @override
  Future<String?> transcribe(Uint8List pcm, {required String accessToken}) {
    calls++;
    return result.future;
  }

  @override
  void cancel() {}
}

class _Recorder extends RecordPlatform {
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
  Future<String?> stop(String recorderId) async => null;
  @override
  Future<void> cancel(String recorderId) async {}
  @override
  Future<void> dispose(String recorderId) async => audio.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
