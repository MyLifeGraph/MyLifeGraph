import 'dart:typed_data';

/// One cancellable upload. Transport types never escape into the recording UI.
abstract interface class CoachDictationRequest {
  Future<String?> transcribe(Uint8List pcm, {required String accessToken});

  void cancel();
}
