import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

// UI guard only; mutation identity is still derived by the existing backend.
final captureDraftOwnerProvider = Provider<String?>((ref) {
  final auth = ref.watch(authControllerProvider);
  final session = auth.valueOrNull;
  if (auth.isLoading ||
      auth.hasError ||
      session == null ||
      !session.isAuthenticated ||
      session.isGuestSession ||
      session.isDeletionRecovery) {
    return null;
  }
  return session.profile.id;
});
