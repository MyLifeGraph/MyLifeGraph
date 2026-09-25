import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appHapticsProvider = AsyncNotifierProvider<AppHapticsController, bool>(
  AppHapticsController.new,
);

/// Device-local UI feedback only; never records a product outcome.
class AppHapticsController extends AsyncNotifier<bool> {
  static const preferenceKey = 'app_haptic_feedback';
  bool _saving = false;
  bool _disposed = false;
  final _clock = Stopwatch()..start();
  int? _lastPulse;

  @override
  Future<bool> build() async {
    ref.onDispose(() => _disposed = true);
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(preferenceKey) ?? true;
  }

  Future<bool> select(bool enabled) async {
    if (_saving || !state.hasValue) return false;
    _saving = true;
    final previous = state.requireValue;
    state = AsyncData(enabled);
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setBool(preferenceKey, enabled)) {
        throw StateError('Haptic preference was not saved.');
      }
      return true;
    } catch (_) {
      if (!_disposed) state = AsyncData(previous);
      return false;
    } finally {
      _saving = false;
    }
  }

  Future<void> selection() async {
    // No pulse before restore, on web/desktop, or if local storage failed.
    if (_disposed || state.valueOrNull != true || kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    final now = _clock.elapsedMilliseconds;
    if (_lastPulse != null && now - _lastPulse! < 100) return;
    _lastPulse = now;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {
      // Unsupported hardware must never interrupt an action.
    }
  }
}

/// Optional in isolated widget previews. Production installs this at app root.
class AppHaptics extends InheritedWidget {
  const AppHaptics({
    required this.onSelection,
    required super.child,
    super.key,
  });

  final VoidCallback onSelection;

  static void selection(BuildContext context) {
    context.getInheritedWidgetOfExactType<AppHaptics>()?.onSelection();
  }

  static VoidCallback? action(BuildContext context, VoidCallback? action) {
    if (action == null) return null;
    return () {
      selection(context);
      action();
    };
  }

  @override
  bool updateShouldNotify(AppHaptics oldWidget) => false;
}
