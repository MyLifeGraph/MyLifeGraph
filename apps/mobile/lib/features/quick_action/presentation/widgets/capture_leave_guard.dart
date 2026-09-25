import 'package:flutter/material.dart';

Future<bool> confirmCaptureDiscard(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    ) ==
    true;

/// Keeps incomplete captures local; only the existing Save commits answers.
class CaptureLeaveGuard extends StatefulWidget {
  const CaptureLeaveGuard({
    super.key,
    required this.dirty,
    required this.saving,
    required this.onLeave,
    required this.builder,
  });
  final bool dirty;
  final bool saving;
  final VoidCallback onLeave;
  final Widget Function(VoidCallback requestLeave) builder;

  @override
  State<CaptureLeaveGuard> createState() => _CaptureLeaveGuardState();
}

class _CaptureLeaveGuardState extends State<CaptureLeaveGuard> {
  bool _leaving = false;
  bool _asking = false;

  Future<void> _leave() async {
    if (_asking || _leaving || widget.saving) return;
    if (widget.dirty) {
      _asking = true;
      final discard = await confirmCaptureDiscard(context);
      _asking = false;
      if (!mounted || discard != true || widget.saving) return;
    }
    setState(() => _leaving = true);
    // PopScope must rebuild before the explicit, approved navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLeave();
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving || (!widget.dirty && !widget.saving),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: widget.builder(_leave),
  );
}
