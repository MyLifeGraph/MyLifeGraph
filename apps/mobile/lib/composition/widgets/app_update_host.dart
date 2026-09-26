import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/app_updates/application/app_updates.dart';
import '../../features/app_updates/presentation/update_dialog.dart';

/// Runs only after entering the product shell, never blocking sign-in or boot.
class AppUpdateHost extends ConsumerStatefulWidget {
  const AppUpdateHost({
    required this.child,
    required this.allowPrompt,
    super.key,
  });
  final Widget child;
  final bool allowPrompt;

  @override
  ConsumerState<AppUpdateHost> createState() => _AppUpdateHostState();
}

class _AppUpdateHostState extends ConsumerState<AppUpdateHost>
    with WidgetsBindingObserver {
  bool _presenting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppUpdateHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.allowPrompt && widget.allowPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (!mounted || !ref.read(appUpdatesSupportedProvider)) return;
    final controller = ref.read(appUpdatesProvider.notifier);
    await controller.check();
    if (!_canPrompt || _presenting) return;
    final update = ref.read(appUpdatesProvider).update;
    if (update == null) return;
    _presenting = true;
    try {
      if (!await controller.claimNotice(update) || !mounted || !_canPrompt) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (_) => AppUpdateDialog(update: update),
      );
    } finally {
      _presenting = false;
    }
  }

  bool get _canPrompt {
    if (!mounted ||
        !widget.allowPrompt ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) ||
        ModalRoute.of(context)?.isCurrent != true ||
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
