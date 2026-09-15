import 'dart:typed_data';
import '../domain/speech_models.dart';

class LocalSpeechStore {
  bool get supported => false;
  Future<bool> installed(SpeechModel model) async => false;
  Future<void> download(
    SpeechModel model,
    void Function(double) progress,
  ) async => throw UnsupportedError('On-device speech requires Android.');
  void cancelDownload() {}
  Future<void> remove(SpeechModel model) async {}
  Future<String?> transcribe(SpeechModel model, Uint8List pcm) async =>
      throw UnsupportedError('On-device speech requires Android.');
}
