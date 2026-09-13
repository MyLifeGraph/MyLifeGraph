import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/capabilities/app_surface_capabilities.dart';
import '../features/insights/presentation/providers/insights_providers.dart';
import 'auth_providers.dart';

// Insights-only display choices for the account session; never gate Capture.
final skillsetDimensionsProvider = StateProvider<Set<String>>((ref) {
  ref.watch(
    authControllerProvider.select((value) => value.valueOrNull?.profile.id),
  );
  return {'sleep', 'sport', 'energy', 'social', 'learning', 'concentration'};
});

final optionalSkillsetCaptureProvider = Provider<bool>(
  (ref) =>
      ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo ||
      (ref
              .watch(personalPatternsProvider)
              .valueOrNull
              ?.supportsSkillsetCapture ??
          false),
);
