import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local_speech.dart';
import '../domain/coach_dictation_request.dart';
import '../domain/speech_models.dart';

final speechSettingsProvider = ChangeNotifierProvider<SpeechSettings>(
  (ref) => SpeechSettings(LocalSpeechStore()),
);

/// Device preferences and model files, never cloud account data or credentials.
class SpeechSettings extends ChangeNotifier {
  SpeechSettings(this.store) {
    ready = _load();
  }
  final LocalSpeechStore store;
  late final Future<void> ready;
  String source = 'server';
  final Set<String> installed = {};
  String? downloading;
  double progress = 0;
  String? error;
  bool loading = true;
  bool initializationFailed = false;
  bool _disposed = false;
  bool get supported => store.supported;
  String get label => source == 'server' ? 'Server' : speechModel(source).label;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('speech_source_v1');
      // Do not silently upload audio if a previously selected model is missing.
      if (supported && speechModels.any((m) => m.id == saved)) source = saved!;
      for (final model in speechModels) {
        if (await store.installed(model)) installed.add(model.id);
      }
    } catch (_) {
      initializationFailed = true;
      error = 'Speech settings could not be loaded. Try reopening the app.';
    }
    loading = false;
    _notify();
  }

  Future<void> select(String id) async {
    await ready;
    if (id != 'server' && (!supported || !installed.contains(id))) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString('speech_source_v1', id)) {
        throw StateError('Save failed');
      }
      source = id;
      initializationFailed = false;
      error = null;
    } catch (_) {
      error = 'Could not save the speech source. Try again.';
    }
    _notify();
  }

  Future<void> download(SpeechModel model) async {
    if (downloading != null) return;
    downloading = model.id;
    progress = 0;
    error = null;
    _notify();
    try {
      await store.download(model, (value) {
        progress = value;
        _notify();
      });
      if (await store.installed(model)) installed.add(model.id);
    } catch (_) {
      error = 'Download stopped. Check storage and connection, then retry.';
    } finally {
      downloading = null;
      _notify();
    }
  }

  Future<void> remove(SpeechModel model) async {
    // Switching to server must be explicit; deleting a model cannot enable uploads.
    if (source == model.id || downloading != null) return;
    try {
      await store.remove(model);
      installed.remove(model.id);
      error = null;
    } catch (_) {
      error = 'Model is in use. Try again after transcription.';
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    store.cancelDownload();
    super.dispose();
  }
}

class OnDeviceDictationRequest implements CoachDictationRequest {
  OnDeviceDictationRequest(this.store, this.model);
  final LocalSpeechStore store;
  final SpeechModel model;
  bool _cancelled = false;
  @override
  void cancel() => _cancelled = true;
  @override
  Future<String?> transcribe(
    Uint8List pcm, {
    required String accessToken,
  }) async {
    if (_cancelled) return null;
    // No token, audio, or text leaves the device through this request.
    final text = await store.transcribe(model, pcm);
    return _cancelled ? null : text;
  }
}
