import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../data/guest_quick_check_in_data_source.dart';
import '../../data/quick_check_in_supabase_data_source.dart';
import '../../domain/quick_check_in.dart';

final quickCheckInStoreProvider = Provider<QuickCheckInStore>((ref) {
  if (ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo) {
    return GuestQuickCheckInDataSource();
  }

  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    return QuickCheckInSupabaseDataSource(client);
  }
  return const _UnavailableQuickCheckInStore();
});

final latestQuickCheckInProvider =
    FutureProvider.autoDispose<QuickCheckInDraft?>((ref) {
  return ref.watch(quickCheckInStoreProvider).loadToday(DateTime.now());
});

class _UnavailableQuickCheckInStore implements QuickCheckInStore {
  const _UnavailableQuickCheckInStore();

  @override
  QuickCheckInSaveTarget get target => QuickCheckInSaveTarget.supabase;

  @override
  Future<QuickCheckInDraft?> loadToday(DateTime today) async => null;

  @override
  Future<void> save(QuickCheckInDraft draft) {
    throw const QuickCheckInUnavailableException(
      'Supabase is not configured for this account.',
    );
  }
}
