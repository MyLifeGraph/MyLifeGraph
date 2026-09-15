class SpeechModelFile {
  const SpeechModelFile(this.name, this.bytes, this.sha256);
  final String name;
  final int bytes;
  final String sha256;
}

class SpeechModel {
  const SpeechModel(
    this.id,
    this.label,
    this.repository,
    this.revision,
    this.files,
  );
  final String id, label, repository, revision;
  final List<SpeechModelFile> files;
  int get bytes => files.fold(0, (sum, file) => sum + file.bytes);
  String url(SpeechModelFile file) =>
      'https://huggingface.co/$repository/resolve/$revision/${file.name}';
}

const speechModels = [
  SpeechModel(
    'whisper-tiny',
    'Whisper Tiny',
    'csukuangfj/sherpa-onnx-whisper-tiny',
    '65176e2deb88badc814a94058666cadccc29b61c',
    [
      SpeechModelFile(
        'tiny-encoder.int8.onnx',
        12937772,
        'd24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434',
      ),
      SpeechModelFile(
        'tiny-decoder.int8.onnx',
        89855401,
        'd2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925',
      ),
      SpeechModelFile(
        'tiny-tokens.txt',
        816730,
        'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
      ),
    ],
  ),
  SpeechModel(
    'whisper-base',
    'Whisper Base',
    'csukuangfj/sherpa-onnx-whisper-base',
    'bb53ee204431c90d314c1cc08d28d23e5b7927cc',
    [
      SpeechModelFile(
        'base-encoder.int8.onnx',
        29120534,
        '0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11',
      ),
      SpeechModelFile(
        'base-decoder.int8.onnx',
        130672026,
        '9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d',
      ),
      SpeechModelFile(
        'base-tokens.txt',
        816730,
        'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
      ),
    ],
  ),
  SpeechModel(
    'parakeet-v3',
    'Parakeet V3',
    'csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8',
    '2bda32ec70b097a55adaa07d9a7173915b43cc78',
    [
      SpeechModelFile(
        'encoder.int8.onnx',
        652184281,
        'acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247',
      ),
      SpeechModelFile(
        'decoder.int8.onnx',
        11845275,
        '179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e',
      ),
      SpeechModelFile(
        'joiner.int8.onnx',
        6355277,
        '3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3',
      ),
      SpeechModelFile(
        'tokens.txt',
        93939,
        'd58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d',
      ),
    ],
  ),
];

SpeechModel speechModel(String id) =>
    speechModels.firstWhere((model) => model.id == id);
