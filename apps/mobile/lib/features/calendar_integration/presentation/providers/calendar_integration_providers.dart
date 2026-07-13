import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../application/calendar_ics_file_picker.dart';
import '../../application/calendar_integration_controller.dart';
import '../../data/calendar_integration_api_data_source.dart';
import '../../data/calendar_integration_repository_impl.dart';
import '../../domain/calendar_integration_repository.dart';

final calendarIntegrationApiDataSourceProvider =
    Provider<CalendarIntegrationApiDataSource>(
  (ref) => CalendarIntegrationApiDataSource(ref.watch(apiClientProvider)),
);

final calendarIntegrationAccessTokenProvider =
    Provider<CalendarAccessTokenProvider>(
  (ref) =>
      () => ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken,
);

final calendarIntegrationRepositoryProvider =
    Provider<CalendarIntegrationRepository>((ref) {
  final capabilities = ref.watch(appSurfaceCapabilitiesProvider);
  return CalendarIntegrationRepositoryImpl(
    config: ref.watch(appConfigProvider),
    apiDataSource: ref.watch(calendarIntegrationApiDataSourceProvider),
    accessTokenProvider: ref.watch(calendarIntegrationAccessTokenProvider),
    isLocalDemo: capabilities.isLocalDemo,
    canUseSyncedIntegration: capabilities.canUseCalendarIntegration,
  );
});

final calendarIcsFilePickerProvider = Provider<CalendarIcsFilePicker>(
  (_) => const FileSelectorCalendarIcsFilePicker(),
);

final calendarIntegrationControllerProvider = StateNotifierProvider.autoDispose<
    CalendarIntegrationController, CalendarIntegrationState>((ref) {
  return CalendarIntegrationController(
    repository: ref.watch(calendarIntegrationRepositoryProvider),
    filePicker: ref.watch(calendarIcsFilePickerProvider),
  );
});
