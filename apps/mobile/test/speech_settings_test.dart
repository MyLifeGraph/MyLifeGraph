import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:my_life_graph/core/theme/app_theme.dart';
import 'package:my_life_graph/composition/widgets/speech_settings_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/features/coach/presentation/providers/coach_providers.dart';
import 'package:my_life_graph/features/coach/application/speech_settings.dart';
import 'package:my_life_graph/features/coach/data/local_speech.dart';
import 'package:my_life_graph/features/coach/domain/speech_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final largeText in [false, true]) {
    testWidgets('speech sheets clear Android navigation (large text: $largeText)', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(bottom: 48);
      tester.view.viewPadding = FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      final settings = SpeechSettings(_Store());
      await settings.ready;
      final root = GlobalKey<NavigatorState>();
      final nested = GlobalKey<NavigatorState>();
      await tester.pumpWidget(ProviderScope(
        overrides: [speechSettingsProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          navigatorKey: root,
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(largeText ? 2 : 1)),
            child: child!,
          ),
          home: Scaffold(
            extendBody: true,
            bottomNavigationBar: const SizedBox(height: 96),
            body: Navigator(key: nested, onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const Center(child: SpeechSourceButton()),
            )),
          ),
        ),
      ));
      await tester.tap(find.byType(SpeechSourceButton));
      await tester.pumpAndSettle();
      expect(root.currentState!.canPop(), isTrue);
      expect(nested.currentState!.canPop(), isFalse);
      final serverHint = find.text('Audio is transcribed on our server.');
      await tester.ensureVisible(serverHint);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(serverHint).dy, lessThanOrEqualTo(740 - 48));
      await tester.ensureVisible(find.text('On-device'));
      await tester.tap(find.text('On-device'));
      await tester.pumpAndSettle();
      final download = find.byTooltip('Download Parakeet V3');
      final row = find.ancestor(of: download, matching: find.byType(ListTile));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(download.hitTestable(), findsOneWidget);
      expect(tester.getBottomRight(row).dy, lessThanOrEqualTo(740 - 48));
      expect(tester.takeException(), isNull);
    });
  }

  for (final supported in [true, false]) {
    testWidgets('On-device opens model picker (supported: $supported)', (tester) async {
      final store = supported ? _Store() : _UnsupportedStore();
      store.files.add('whisper-base');
      final settings = SpeechSettings(store);
      await settings.ready;
      await tester.pumpWidget(ProviderScope(
        overrides: [speechSettingsProvider.overrideWith((ref) => settings)],
        child: MaterialApp(theme: AppTheme.dark,
          home: const Scaffold(body: SpeechSourceButton())),
      ));
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('On-device'));
      await tester.pumpAndSettle();
      expect(find.text('Speech to text'), findsOneWidget);
      for (final model in speechModels) {
        expect(find.text(model.label), findsOneWidget);
      }
      final download = tester.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Download Whisper Tiny'));
      expect(download.onPressed, supported ? isNotNull : isNull);
      final parakeet = find.byWidgetPredicate((widget) =>
          widget is IconButton && widget.tooltip == 'Download Parakeet V3');
      await tester.ensureVisible(parakeet);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(parakeet).onPressed,
          supported ? isNotNull : isNull);
      if (supported) {
        await tester.tap(parakeet);
        await tester.pumpAndSettle();
        expect(find.text('Download Parakeet V3?'), findsOneWidget);
        await tester.tap(find.text('Download'));
        await tester.pumpAndSettle();
        expect(settings.installed, contains('parakeet-v3'));
      }
      if (supported) {
        await tester.ensureVisible(find.text('Whisper Base'));
        await tester.tap(find.text('Whisper Base'));
        await tester.pumpAndSettle();
        expect(settings.source, 'whisper-base');
        await tester.tap(find.byTooltip('Download Whisper Tiny'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Download'));
        await tester.pumpAndSettle();
        expect(settings.installed, contains('whisper-tiny'));
        expect(settings.source, 'whisper-base');
      } else {
        expect(settings.source, 'server');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reopened local selection shows the entire model catalog above Android inset', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: 48);
    tester.view.viewPadding = FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final store = _Store()..files.addAll(speechModels.map((m) => m.id));
    final first = SpeechSettings(store);
    await first.ready;
    await first.select('parakeet-v3');
    first.dispose();
    final reopened = SpeechSettings(store);
    await reopened.ready;
    expect(reopened.source, 'parakeet-v3');
    expect(reopened.installed.length, 3);
    await tester.pumpWidget(ProviderScope(
      overrides: [speechSettingsProvider.overrideWith((ref) => reopened)],
      child: MaterialApp(theme: AppTheme.dark,
        home: const Scaffold(body: SpeechSourceButton())),
    ));
    for (var open = 0; open < 2; open++) {
      await tester.tap(find.byType(SpeechSourceButton));
      await tester.pumpAndSettle();
      for (final model in speechModels) {
        expect(find.text(model.label).hitTestable(), findsOneWidget);
      }
      expect(find.textContaining('Selected'), findsOneWidget);
      expect(find.textContaining('Downloaded'), findsNWidgets(2));
      final last = find.ancestor(of: find.text('Parakeet V3'), matching: find.byType(ListTile));
      expect(tester.getBottomRight(last).dy, lessThanOrEqualTo(752));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  test('installed local speech permits a signed-in draft, never guest or server fallback', () async {
    final speech = SpeechSettings(_Store());
    await speech.ready;
    await speech.download(speechModels.first);
    await speech.select('whisper-tiny');
    final profile = StateProvider<String?>((ref) => 'signed-in');
    final container = ProviderContainer(overrides: [
      speechSettingsProvider.overrideWith((ref) => speech),
      appConfigProvider.overrideWithValue(AppConfig(environment: 'pilot', supabaseUrl: '', aiServiceBaseUrl: '', useMockData: false)),
      coachActiveProfileIdProvider.overrideWith((ref) => ref.watch(profile)),
    ]);
    addTearDown(container.dispose);
    expect(container.read(coachLocalDictationProvider), isTrue);
    await speech.select('server');
    expect(container.read(coachLocalDictationProvider), isFalse);
    await speech.select('whisper-tiny');
    container.read(profile.notifier).state = null;
    expect(container.read(coachLocalDictationProvider), isFalse);
  });

  test('catalog is pinned, multilingual and includes all three models', () {
    expect(speechModels.map((m) => m.id), [
      'whisper-tiny',
      'whisper-base',
      'parakeet-v3',
    ]);
    for (final model in speechModels) {
      expect(model.revision, matches(RegExp(r'^[a-f0-9]{40}$')));
      expect(model.bytes, greaterThan(0));
      for (final file in model.files) {
        expect(file.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(Uri.parse(model.url(file)).host, 'huggingface.co');
        expect(model.url(file), contains('/resolve/${model.revision}/'));
      }
    }
  });

  test(
    'server default, explicit download then selection survives reopening',
    () async {
      final store = _Store();
      final settings = SpeechSettings(store);
      addTearDown(settings.dispose);
      await settings.ready;
      expect(settings.source, 'server');
      await settings.select('whisper-tiny');
      expect(settings.source, 'server');
      await settings.download(speechModels.first);
      expect(
        settings.source,
        'server',
        reason: 'Download never switches source',
      );
      await settings.select('whisper-tiny');
      final reopened = SpeechSettings(store);
      addTearDown(reopened.dispose);
      await reopened.ready;
      expect(reopened.source, 'whisper-tiny');
      await reopened.remove(speechModels.first);
      expect(
        store.files,
        contains('whisper-tiny'),
        reason: 'No implicit fallback/upload on removal',
      );
      await reopened.select('server');
      await reopened.remove(speechModels.first);
      expect(store.files, isEmpty);
    },
  );

  test('missing selected model never silently falls back to server', () async {
    SharedPreferences.setMockInitialValues({'speech_source_v1': 'parakeet-v3'});
    final settings = SpeechSettings(_Store());
    addTearDown(settings.dispose);
    await settings.ready;
    expect(settings.source, 'parakeet-v3');
    expect(settings.installed, isEmpty);
  });

  test(
    'cancelled local transcription discards result and passes no credential',
    () async {
      final store = _Store();
      final request = OnDeviceDictationRequest(store, speechModels.first);
      final result = request.transcribe(
        Uint8List(3200),
        accessToken: 'must-stay-unused',
      );
      request.cancel();
      store.result.complete('discard this');
      expect(await result, isNull);
    },
  );
}

class _Store extends LocalSpeechStore {
  final files = <String>{};
  final result = Completer<String?>();
  @override
  bool get supported => true;
  @override
  Future<bool> installed(SpeechModel model) async => files.contains(model.id);
  @override
  Future<void> download(
    SpeechModel model,
    void Function(double) progress,
  ) async {
    files.add(model.id);
    progress(1);
  }

  @override
  Future<void> remove(SpeechModel model) async {
    files.remove(model.id);
  }

  @override
  Future<String?> transcribe(SpeechModel model, Uint8List pcm) => result.future;
}

class _UnsupportedStore extends _Store {
  @override
  bool get supported => false;
}
