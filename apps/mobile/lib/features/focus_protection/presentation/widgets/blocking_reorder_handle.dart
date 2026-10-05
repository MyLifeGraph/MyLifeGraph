import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/feedback/app_haptics.dart';

/// Arms a plan drag after a deliberate hold, leaving early swipes to scrolling.
class BlockingReorderHandle extends StatelessWidget {
  const BlockingReorderHandle({
    required this.index,
    required this.child,
    this.enabled = true,
    super.key,
  });

  static const holdDuration = Duration(seconds: 1);

  final int index;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => _DelayedReorderListener(
    index: index,
    enabled: enabled,
    onDragStarted: () => AppHaptics.selection(context),
    // The six dots have gaps. The whole 44px handle must receive pointer downs,
    // including a finger placed between the dots rather than on a painted dot.
    child: Listener(behavior: HitTestBehavior.opaque, child: child),
  );
}

class _DelayedReorderListener extends ReorderableDragStartListener {
  const _DelayedReorderListener({
    required super.index,
    required super.child,
    required super.enabled,
    required this.onDragStarted,
  });

  final VoidCallback onDragStarted;

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      _FeedbackDragRecognizer(onDragStarted: onDragStarted, debugOwner: this);
}

class _FeedbackDragRecognizer extends DelayedMultiDragGestureRecognizer {
  _FeedbackDragRecognizer({required this.onDragStarted, super.debugOwner})
    : super(delay: BlockingReorderHandle.holdDuration);

  final VoidCallback onDragStarted;

  @override
  set onStart(GestureMultiDragStartCallback? callback) {
    super.onStart = (position) {
      final drag = callback?.call(position);
      if (drag != null) onDragStarted();
      return drag;
    };
  }
}
