import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_life_graph/features/coach/application/speech_settings.dart';
import 'package:my_life_graph/features/coach/data/local_speech.dart';
import 'package:my_life_graph/features/coach/domain/speech_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
