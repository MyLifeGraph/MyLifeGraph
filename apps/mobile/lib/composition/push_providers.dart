import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../core/platform/push_platform.dart';
import '../core/supabase/supabase_providers.dart';
import '../core/capabilities/app_surface_capabilities.dart';
import '../features/notifications/application/push_controller.dart';
import 'auth_providers.dart';

final pushProvider =
    StateNotifierProvider.autoDispose<PushController, PushView>((ref) {
      final owner = ref.watch(authControllerProvider).valueOrNull?.profile.id;
      final allowed = ref
          .watch(appSurfaceCapabilitiesProvider)
          .canUseSyncedExecution;
      final client = ref.watch(supabaseClientProvider);
      final session = client?.auth.currentSession;
      if (!allowed || owner == null || session?.user.id != owner) {
        throw StateError('Real account required');
      }
      final claims =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    base64Url.normalize(session!.accessToken.split('.')[1]),
                  ),
                ),
              )
              as Map<String, dynamic>;
      final sessionId = claims['session_id'] as String;
      return PushController(
        ref.watch(apiClientProvider),
        const PushPlatform(),
        () {
          final current = client?.auth.currentSession;
          if (current?.user.id != owner) throw StateError('Account changed');
          final active =
              jsonDecode(
                    utf8.decode(
                      base64Url.decode(
                        base64Url.normalize(current!.accessToken.split('.')[1]),
                      ),
                    ),
                  )
                  as Map<String, dynamic>;
          if (active['session_id'] != sessionId) {
            throw StateError('Session changed');
          }
          return current.accessToken;
        },
        owner,
        sessionId,
        android: PushPlatform.supported,
      );
    });
