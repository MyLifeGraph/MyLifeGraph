import 'package:flutter/material.dart';
import 'capture_dictation_input.dart';

/// Speech appends only to the reviewed note, never to numeric Capture answers.
class CaptureNoteField extends StatefulWidget {
  const CaptureNoteField({
    required this.controller,
    required this.onChanged,
    required this.onBusyChanged,
    this.enabled = true,
    this.label = 'Note (optional)',
    this.hint,
    this.maxLines = 4,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onBusyChanged;
  final bool enabled;
  final String label;
  final String? hint;
  final int maxLines;

  @override
  State<CaptureNoteField> createState() => _CaptureNoteFieldState();
}

class _CaptureNoteFieldState extends State<CaptureNoteField> {
  bool _busy = false;

  void _append(String transcript) {
    if (!mounted || !widget.enabled) return;
    final original = widget.controller.text;
    final next = [
      original.trimRight(),
      transcript.trim(),
    ].where((part) => part.isNotEmpty).join('\n');
    if (next.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Keep your note under 500 characters. Recording not added.',
          ),
        ),
      );
      return;
    }
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    Widget field([Widget? microphone]) => TextField(
      controller: widget.controller,
      enabled: widget.enabled && !_busy,
      maxLength: 500,
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        alignLabelWithHint: true,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        counterText: '',
        contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
        suffixIcon: microphone,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy) field(),
        CaptureDictationInput(
          enabled: widget.enabled,
          onText: _append,
          onBusyChanged: (value) {
            if (!mounted) return;
            setState(() => _busy = value);
            widget.onBusyChanged(value);
          },
          idleBuilder: (microphone) => Stack(
            children: [
              field(microphone),
              Positioned(
                right: 12,
                bottom: 10,
                child: Text(
                  '${widget.controller.text.length}/500',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
