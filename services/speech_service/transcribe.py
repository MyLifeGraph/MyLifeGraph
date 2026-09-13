"""Read bounded raw PCM from stdin; output text JSON only. Never store audio."""
import json
import os
import sys
from pathlib import Path


def main() -> None:
    import numpy as np
    import sherpa_onnx

    maximum = 16000 * 2 * 30
    audio = sys.stdin.buffer.read(maximum + 1)
    if not 3200 <= len(audio) <= maximum or len(audio) % 2:
        raise ValueError('Invalid PCM length')
    model = Path(os.environ['SPEECH_MODEL_DIR'])
    recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
        tokens=str(model / 'tokens.txt'), encoder=str(model / 'encoder.int8.onnx'),
        decoder=str(model / 'decoder.int8.onnx'), joiner=str(model / 'joiner.int8.onnx'),
        num_threads=2, sample_rate=16000, feature_dim=80,
        decoding_method='greedy_search', model_type='nemo_transducer', debug=False,
        provider='cpu',
    )
    samples = np.frombuffer(audio, dtype='<i2').astype(np.float32) / 32768.0
    stream = recognizer.create_stream()
    stream.accept_waveform(16000, samples)
    recognizer.decode_stream(stream)
    print(json.dumps({'text': stream.result.text.strip()}, ensure_ascii=True))


if __name__ == '__main__':
    main()
