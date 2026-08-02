import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/capabilities/app_surface_capabilities.dart';
import '../core/network/api_client.dart';
import '../core/supabase/supabase_providers.dart';
import '../features/focus/data/focus_session_supabase_data_source.dart';
import '../features/quick_action/data/guest_quick_check_in_data_source.dart';
import '../features/quick_action/data/quick_check_in_supabase_data_source.dart';
import '../features/quick_action/domain/quick_check_in.dart';
import 'package:my_life_graph/composition/profile_local_date_providers.dart';

final quickCheckInStoreProvider = Provider<QuickCheckInStore>((ref) {
  if (ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo) {
    return GuestQuickCheckInDataSource();
  }

  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    return QuickCheckInSupabaseDataSource(
      client,
      apiClient: ref.watch(apiClientProvider),
    );
  }
  return const _UnavailableQuickCheckInStore();
});

final latestQuickCheckInProvider =
    FutureProvider.autoDispose<DailyCaptureEntry?>((ref) {
  return ref
      .watch(quickCheckInStoreProvider)
      .loadToday(ref.watch(profileLocalDateSourceProvider).today());
});

final eveningFocusReflectionSourceProvider =
    Provider<FocusSessionSupabaseDataSource?>((ref) {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  final client = ref.watch(supabaseClientProvider);
  if (capabilities.isLocalDemo ||
      !capabilities.canUseSyncedExecution ||
      client?.auth.currentUser == null) {
    return null;
  }
  final profileDate = ref.watch(profileLocalDateSourceProvider);
  return FocusSessionSupabaseDataSource(
    client!,
    entryDateProvider: profileDate.dateKeyAt,
    apiClient: ref.watch(apiClientProvider),
    accessTokenProvider: () async =>
        ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
  );
});

class _UnavailableQuickCheckInStore implements QuickCheckInStore {
  const _UnavailableQuickCheckInStore();

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.supabase;

  @override
  Future<DailyCaptureEntry?> loadToday(DateTime today) async => null;

  @override
  Future<EveningShutdownDraft?> loadLatestEvening() async => null;

  @override
  Future<void> saveEvening(EveningShutdownDraft draft) {
    throw const QuickCheckInUnavailableException(
      'Supabase is not configured for this account.',
    );
  }

  @override
  Future<void> saveMorning(MorningCalibrationDraft draft) {
    throw const QuickCheckInUnavailableException(
      'Supabase is not configured for this account.',
    );
  }
}
