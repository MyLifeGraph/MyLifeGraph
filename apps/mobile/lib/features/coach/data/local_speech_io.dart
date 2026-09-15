import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../domain/speech_models.dart';

class LocalSpeechStore {
  CancelToken? _download;
  bool _decoding = false;
  bool get supported =>
      Platform.isAndroid &&
      (Abi.current() == Abi.androidArm64 || Abi.current() == Abi.androidX64);
  Future<Directory> _directory(SpeechModel model) async {
    if (!speechModels.contains(model)) {
      throw ArgumentError('Unknown speech model');
    }
    return Directory(
      '${(await getApplicationSupportDirectory()).path}/speech-models-v1/${model.id}',
    );
  }

  Future<bool> installed(SpeechModel model) async {
    if (!supported) return false;
    final directory = await _directory(model);
    final marker = File('${directory.path}/verified');
    if (!await marker.exists() || await marker.readAsString() != model.revision) {
      return false;
    }
    for (final asset in model.files) {
      final file = File('${directory.path}/${asset.name}');
      if (!await file.exists() || await file.length() != asset.bytes) {
        return false;
      }
    }
    return true;
  }

  Future<void> download(
    SpeechModel model,
    void Function(double) progress,
  ) async {
    if (!supported || _download != null || _decoding) {
      throw StateError('Speech operation unavailable');
    }
    final token = _download = CancelToken();
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    var completed = 0;
    try {
      final directory = await _directory(model);
      await directory.create(recursive: true);
      for (final asset in model.files) {
        if (token.isCancelled) throw token.cancelError!;
        final file = File('${directory.path}/${asset.name}');
        if (await file.exists() &&
            await file.length() == asset.bytes &&
            (await sha256.bind(file.openRead()).first).toString() ==
                asset.sha256) {
          completed += asset.bytes;
          progress(completed / model.bytes);
          continue;
        }
        final part = File('${file.path}.part');
        try {
          final response = await dio.get<ResponseBody>(
            model.url(asset),
            options: Options(responseType: ResponseType.stream),
            cancelToken: token,
          );
          final output = await part.open(mode: FileMode.write);
          var received = 0;
          try {
            await for (final chunk in response.data!.stream) {
              if (token.isCancelled) throw token.cancelError!;
              received += chunk.length;
              if (received > asset.bytes) {
                throw StateError('Model download exceeds expected size');
              }
              await output.writeFrom(chunk);
              progress((completed + received) / model.bytes);
            }
          } finally {
            await output.close();
          }
          if (received != asset.bytes ||
              (await sha256.bind(part.openRead()).first).toString() !=
                  asset.sha256) {
            throw StateError('Model checksum mismatch');
          }
          if (token.isCancelled) throw token.cancelError!;
          if (await file.exists()) await file.delete();
          await part.rename(file.path);
          completed += asset.bytes;
        } finally {
          if (await part.exists()) await part.delete();
        }
      }
      if (token.isCancelled) throw token.cancelError!;
      await File(
        '${directory.path}/verified',
      ).writeAsString(model.revision, flush: true);
    } finally {
      dio.close(force: true);
      _download = null;
    }
  }

  void cancelDownload() => _download?.cancel();

  Future<void> remove(SpeechModel model) async {
    if (_decoding || _download != null) {
      throw StateError('Speech operation in progress');
    }
    final directory = await _directory(model);
    // Only the fixed catalog files owned by this feature; no recursive deletion.
    for (final name in [
      'verified',
      ...model.files.expand((f) => [f.name, '${f.name}.part']),
    ]) {
      final file = File('${directory.path}/$name');
      if (await file.exists()) await file.delete();
    }
  }

  Future<String?> transcribe(SpeechModel model, Uint8List pcm) async {
    if (_decoding || _download != null) {
      throw StateError('Speech operation in progress');
    }
    _decoding = true;
    try {
      if (pcm.length < 3200 ||
          pcm.length > 960000 ||
          pcm.length.isOdd ||
          !await installed(model)) {
        throw StateError('Download the model before recording');
      }
      final path = (await _directory(model)).path;
      final text = await _runLocalDecode(model.id, path, pcm);
      return text.isEmpty || text.runes.length > 2000 ? null : text;
    } finally {
      _decoding = false;
    }
  }
}

// A top-level launch scope prevents capturing the store/plugin state in a closure.
Future<String> _runLocalDecode(String id, String path, Uint8List pcm) =>
    Isolate.run(() => decodeLocalSpeech(id, path, pcm));

// Native recognizers are created/freed in the worker, never on the Flutter UI thread.
String decodeLocalSpeech(String id, String directory, Uint8List pcm) {
  sherpa.initBindings();
  final model = speechModel(id);
  final isWhisper = id.startsWith('whisper-');
  final config = sherpa.OfflineModelConfig(
    whisper: isWhisper
        ? sherpa.OfflineWhisperModelConfig(
            encoder: '$directory/${model.files[0].name}',
            decoder: '$directory/${model.files[1].name}',
            language: '',
            task: 'transcribe',
          )
        : const sherpa.OfflineWhisperModelConfig(),
    transducer: !isWhisper
        ? sherpa.OfflineTransducerModelConfig(
            encoder: '$directory/encoder.int8.onnx',
            decoder: '$directory/decoder.int8.onnx',
            joiner: '$directory/joiner.int8.onnx',
          )
        : const sherpa.OfflineTransducerModelConfig(),
    tokens: '$directory/${model.files.last.name}',
    numThreads: 2,
    provider: 'cpu',
    modelType: isWhisper ? 'whisper' : 'nemo_transducer',
  );
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(model: config),
  );
  try {
    final stream = recognizer.createStream();
    try {
      final bytes = ByteData.sublistView(pcm);
      final samples = Float32List(pcm.length ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = bytes.getInt16(i * 2, Endian.little) / 32768;
      }
      stream.acceptWaveform(samples: samples, sampleRate: 16000);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  } finally {
    recognizer.free();
  }
}
