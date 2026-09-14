import 'package:flutter/material.dart';

import '../../features/coach/presentation/widgets/coach_dictation_button.dart';

/// App composition reuses the existing bounded, session-safe speech recorder.
class CaptureDictationInput extends StatelessWidget {
  const CaptureDictationInput({
    required this.enabled,
    required this.onText,
    required this.onBusyChanged,
    super.key,
  });

  final bool enabled;
  final ValueChanged<String> onText;
  final ValueChanged<bool> onBusyChanged;

  @override
  Widget build(BuildContext context) => CoachDictationButton(
    enabled: enabled,
    onText: (text, _) => onText(text),
    onBusyChanged: onBusyChanged,
    consentTitle: 'Dictate your check-in',
    consentEnding: 'Stop to review your words. Nothing is saved yet.',
  );
}
