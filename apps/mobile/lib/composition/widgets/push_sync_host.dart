import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/capabilities/app_surface_capabilities.dart';
import '../../core/navigation/app_router.dart';
import '../../core/platform/push_platform.dart';
import '../auth_providers.dart';
import '../push_providers.dart';

class PushSyncHost extends ConsumerStatefulWidget {
  const PushSyncHost({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<PushSyncHost> createState() => _PushSyncHostState();
}

class _PushSyncHostState extends ConsumerState<PushSyncHost>
    with WidgetsBindingObserver {
  String? _owner;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted || _owner == null) return;
    final owner = _owner;
    try {
      await ref.read(pushProvider.notifier).refresh();
      if (!mounted || _owner != owner) return;
      final route = await const PushPlatform().call<String>('takeRoute');
      if (!mounted || _owner != owner) return;
      if (route == '/planner' || route == '/insights') {
        ref.read(appRouterProvider).push(route!);
      }
    } catch (_) {
      /* The optional settings page exposes failures; no app boot failure. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final enabled =
        PushPlatform.supported &&
        ref.watch(appSurfaceCapabilitiesProvider).canUseSyncedExecution;
    final owner = enabled ? auth.valueOrNull?.profile.id : null;
    if (owner != null) {
      // Optional integration errors must not prevent the application from opening.
      try {
        ref.watch(pushProvider);
      } catch (_) {
        // The settings surface can expose an unavailable session.
      }
    }
    if (owner != _owner) {
      final previousOwner = _owner;
      _owner = owner;
      if (owner != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(_refresh()),
        );
      } else if (previousOwner != null && !auth.isLoading) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => unawaited(PushPlatform.clearForSignOut()),
        );
      }
    }
    return widget.child;
  }
}
