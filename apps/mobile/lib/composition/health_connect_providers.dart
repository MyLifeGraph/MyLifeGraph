import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/health_connect/application/health_connect_controller.dart';
import '../features/health_connect/data/health_connect_gateway.dart';
import 'auth_providers.dart';

final healthConnectProvider =
    StateNotifierProvider.autoDispose<
      HealthConnectController,
      HealthConnectViewState
    >((ref) {
      final owner = ref.watch(authControllerProvider).valueOrNull?.profile.id;
      final allowed = ref
          .watch(appSurfaceCapabilitiesProvider)
          .canUseSyncedExecution;
      final supabase = ref.watch(supabaseClientProvider);
      final gateway = HealthConnectGateway(ref.watch(apiClientProvider), () {
        final session = supabase?.auth.currentSession;
        if (!allowed || owner == null || session?.user.id != owner) {
          throw StateError('A real signed-in account is required.');
        }
        return session!.accessToken;
      });
      return HealthConnectController(
        gateway,
        android: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      );
    });
