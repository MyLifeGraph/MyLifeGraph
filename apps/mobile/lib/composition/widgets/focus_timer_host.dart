import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/app_router.dart';
import '../../core/navigation/app_routes.dart';
import '../../features/focus/application/focus_timer_gateway.dart';

class FocusTimerHost extends ConsumerStatefulWidget {
  const FocusTimerHost({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<FocusTimerHost> createState() => _FocusTimerHostState();
}

class _FocusTimerHostState extends ConsumerState<FocusTimerHost>
    with WidgetsBindingObserver {
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_open()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_open());
  }

  Future<void> _open() async {
    if (!mounted || _opening) return;
    _opening = true;
    try {
      final id = await ref.read(focusTimerGatewayProvider).takeOpen();
      if (!mounted ||
          id == null ||
          !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
        return;
      }
      final router = ref.read(appRouterProvider);
      final current = router.routeInformationProvider.value.uri;
      if (current.path == AppRoutes.deepWork &&
          (current.queryParameters['session_id'] == null ||
              current.queryParameters['session_id'] == id)) {
        return;
      }
      unawaited(
        router.push(
          Uri(
            path: AppRoutes.deepWork,
            queryParameters: {'session_id': id},
          ).toString(),
        ),
      );
    } catch (_) {
      /* Optional local reminder cannot prevent application startup. */
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
