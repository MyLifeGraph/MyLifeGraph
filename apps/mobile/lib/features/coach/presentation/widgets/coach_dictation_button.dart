import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/constants/app_radii.dart';
import '../../../../core/network/api_failure.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_visual_tokens.dart';
import '../../domain/coach_dictation_request.dart';
import '../providers/coach_providers.dart';

/// Recording belongs to this route, never to the persistent Coach conversation.
class CoachDictationButton extends ConsumerStatefulWidget {
  const CoachDictationButton({
    required this.enabled,
    required this.onText,
    required this.onBusyChanged,
    this.canSendDirect = false,
    this.idleBuilder,
    super.key,
  });

  final bool enabled;
  final void Function(String text, bool sendNow) onText;
  final ValueChanged<bool> onBusyChanged;
  final bool canSendDirect;
  final Widget Function(Widget microphone)? idleBuilder;

  @override
  ConsumerState<CoachDictationButton> createState() =>
      _CoachDictationButtonState();
}

class _CoachDictationButtonState extends ConsumerState<CoachDictationButton>
    with WidgetsBindingObserver {
  static const _maxBytes = 16000 * 2 * 30;
  AudioRecorder? _recorder;
  final _audio = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  CoachDictationRequest? _request;
  bool _recording = false;
  bool _busy = false;
  bool _askingConsent = false;
  int _secondsLeft = 30;
  final _levels = List<double>.filled(12, 0, growable: true);
  int _generation = 0;
  String? _profile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _request?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_recorder?.dispose());
    _audio.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_cancel());
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _setBusy(bool busy) {
    if (!mounted) return;
    setState(() => _busy = busy);
    widget.onBusyChanged(busy);
  }

  Future<void> _cancel() async {
    _generation++;
    _timer?.cancel();
    _request?.cancel();
    await _subscription?.cancel();
    await _recorder?.cancel();
    _audio.clear();
    _recording = false;
    _setBusy(false);
  }

  Future<void> _start() async {
    if (_busy || _askingConsent || !widget.enabled) return;
    _profile = ref.read(coachActiveProfileIdProvider);
    if (_profile == null) return;
    final consent = ref.read(coachDictationConsentProvider.notifier);
    final int consentGeneration = _generation;
    bool? accepted = consent.state;
    if (!accepted) {
      _askingConsent = true;
      try {
        accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Dictate your question'),
            content: const Text(
              'Record up to 30 seconds. Audio is sent to the '
              'MyLifeGraph server for transcription and is not saved. '
              'Stop to review the text, or Send to ask your Coach directly.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Record'),
              ),
            ],
          ),
        );
      } finally {
        _askingConsent = false;
      }
    }
    if (accepted != true ||
        !mounted ||
        consentGeneration != _generation ||
        !widget.enabled ||
        ref.read(coachActiveProfileIdProvider) != _profile ||
        !identical(consent, ref.read(coachDictationConsentProvider.notifier))) {
      return;
    }
    consent.state = true;
    final generation = ++_generation;
    _setBusy(true);
    try {
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        _message('Allow microphone access to dictate.');
        _setBusy(false);
        return;
      }
      if (!mounted || generation != _generation) return;
      _audio.clear();
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      if (!mounted || generation != _generation) {
        await recorder.cancel();
        return;
      }
      setState(() {
        _recording = true;
        _secondsLeft = 30;
        _levels.fillRange(0, _levels.length, 0);
      });
      _subscription = stream.listen(
        (chunk) {
          if (!mounted || generation != _generation) return;
          final remaining = _maxBytes - _audio.length;
          if (remaining > 0) {
            _audio.add(
              chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
            );
          }
          if (_audio.length >= _maxBytes) {
            unawaited(_finish());
          }
          if (!_recording) {
            return; // Keep final PCM during stop, not its animation.
          }
          // PCM16 mono samples already in memory; no extra audio capture/store.
          final pcm = ByteData.sublistView(chunk);
          var peak = 0.0;
          for (var i = 0; i + 1 < pcm.lengthInBytes; i += 32) {
            final level = pcm.getInt16(i, Endian.little).abs() / 32768;
            if (level > peak) peak = level;
          }
          // Display gain only: normal speech is far below full-scale PCM.
          // Map -60..-12 dBFS to the bar height; keep silence flat.
          final displayLevel = peak <= 0.001
              ? 0.0
              : ((20 * math.log(peak) / math.ln10 + 60) / 48).clamp(0.0, 1.0);
          setState(() {
            _levels.removeAt(0);
            _levels.add(displayLevel);
          });
        },
        onError: (Object _) {
          _message('Recording failed. Your typed question is unchanged.');
          unawaited(_cancel());
        },
      );
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_recording || generation != _generation) {
          timer.cancel();
          return;
        }
        setState(() => _secondsLeft = (30 - timer.tick).clamp(0, 30));
        if (_secondsLeft == 0) unawaited(_finish());
      });
    } catch (_) {
      _message('Microphone unavailable. Check permission and try again.');
      await _cancel();
    }
  }

  Future<void> _finish({bool sendNow = false}) async {
    if (!_recording) return;
    setState(() => _recording = false);
    _timer?.cancel();
    final generation = _generation;
    try {
      await _recorder?.stop();
      await _subscription?.cancel();
      final pcm = _audio.takeBytes();
      if (!mounted || generation != _generation) return;
      if (pcm.length < 3200) {
        _message('Record a little longer, then try again.');
        return;
      }
      final token = await ref.read(coachAccessTokenProvider)();
      if (!mounted ||
          generation != _generation ||
          token == null ||
          ref.read(coachActiveProfileIdProvider) != _profile) {
        return;
      }
      final request = ref.read(coachDictationRequestFactoryProvider)();
      _request = request;
      final text = await request.transcribe(pcm, accessToken: token);
      if (!mounted ||
          generation != _generation ||
          ref.read(coachActiveProfileIdProvider) != _profile) {
        return;
      }
      if (text != null) {
        widget.onText(text, sendNow && widget.canSendDirect);
      } else {
        _message('No speech recognized. Your typed question is unchanged.');
      }
    } on AppException catch (error) {
      final failure = apiFailureFrom(error);
      if (mounted &&
          generation == _generation &&
          failure?.isCancelled != true) {
        _message(
          failure?.statusCode == 429
              ? 'Dictation is busy. Please try again shortly.'
              : 'Transcription unavailable. Your typed question is unchanged.',
        );
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        _message('Transcription failed. Your typed question is unchanged.');
      }
    } finally {
      if (mounted && generation == _generation) {
        _request = null;
        _setBusy(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(coachActiveProfileIdProvider);
    ref.listen(coachActiveProfileIdProvider, (previous, next) {
      if (previous != next && _busy) unawaited(_cancel());
    });
    if (_busy) {
      return Row(
        children: [
          IconButton(
            key: const Key('coach-dictation-discard'),
            tooltip: 'Discard recording',
            onPressed: _cancel,
            icon: const Icon(AppIcons.close),
          ),
          Expanded(
            child: Semantics(
              liveRegion: !_recording,
              child: Row(
                children: [
                  if (_recording)
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: SizedBox(
                              key: const Key('coach-dictation-waveform'),
                              height: 24,
                              child: Row(
                                children: [
                                  for (var i = 0; i < _levels.length; i++)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 1,
                                        ),
                                        child: AnimatedContainer(
                                          key: ValueKey('coach-wave-$i'),
                                          duration:
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 100,
                                                ),
                                          height: 4 + 20 * _levels[i],
                                          decoration: BoxDecoration(
                                            color: context.visualTokens.brand,
                                            borderRadius: BorderRadius.circular(
                                              AppRadii.pill,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Text(
                            '${_secondsLeft}s',
                            key: const Key('coach-dictation-countdown'),
                            semanticsLabel:
                                'Recording. $_secondsLeft seconds remaining',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (!_recording) ...[
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Please wait…')),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            key: const Key('coach-dictation-stop'),
            tooltip: 'Stop and review',
            onPressed: _recording ? () => _finish() : null,
            icon: const Icon(AppIcons.stop),
          ),
          IconButton.filled(
            key: const Key('coach-dictation-send'),
            tooltip: 'Send',
            onPressed: _recording && widget.canSendDirect
                ? () => _finish(sendNow: true)
                : null,
            icon: const Icon(AppIcons.sendOutlined),
          ),
        ],
      );
    }
    final microphone = IconButton(
      key: const Key('coach-dictation-button'),
      tooltip: 'Dictate',
      onPressed: widget.enabled && profile != null ? _start : null,
      icon: const Icon(AppIcons.microphone),
    );
    return widget.idleBuilder?.call(microphone) ?? microphone;
  }
}
