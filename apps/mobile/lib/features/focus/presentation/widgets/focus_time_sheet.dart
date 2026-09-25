import 'package:flutter/material.dart';
import '../../../../core/utils/client_uuid.dart';
import '../../../../core/constants/app_spacing.dart';

class FocusTimeSheet extends StatefulWidget {
  const FocusTimeSheet({
    super.key,
    required this.minutes,
    required this.onSave,
  });
  final int minutes;
  final Future<void> Function(int minutes, String requestId) onSave;
  @override
  State<FocusTimeSheet> createState() => _FocusTimeSheetState();
}

class _FocusTimeSheetState extends State<FocusTimeSheet> {
  late final _text = TextEditingController(text: '${widget.minutes}');
  final _requestId = newClientUuid();
  int? _submittedMinutes;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final minutes = _submittedMinutes ?? int.tryParse(_text.text.trim());
    if (minutes == null || minutes < 0 || minutes > 525600) {
      setState(() => _error = 'Enter valid minutes.');
      return;
    }
    setState(() {
      _submittedMinutes = minutes;
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(minutes, _requestId);
      if (mounted) {
        setState(() => _busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Not confirmed. Retry, or close and refresh.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Correct time'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Within the recorded session. Learning credit updates too.',
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _text,
            enabled: _submittedMinutes == null,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Minutes',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _busy
                ? 'Saving…'
                : _submittedMinutes == null
                ? 'Save'
                : 'Retry',
          ),
        ),
      ],
    ),
  );
}
