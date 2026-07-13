import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/supabase/supabase_providers.dart';
import 'package:my_life_graph/features/calendar_integration/domain/calendar_integration.dart';
import 'package:my_life_graph/features/calendar_integration/presentation/providers/calendar_integration_providers.dart';
import 'package:my_life_graph/features/dashboard/domain/entities/dashboard_snapshot.dart';
import 'package:my_life_graph/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:my_life_graph/features/insights/presentation/providers/insights_providers.dart';
import 'package:my_life_graph/features/quick_action/data/guest_quick_check_in_data_source.dart';
import 'package:my_life_graph/features/quick_action/presentation/providers/quick_check_in_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('local-demo capability keeps check-in, dashboard, and insights local',
      () async {
    final container = ProviderContainer(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(
          const AppSurfaceCapabilities(
            isLocalDemo: true,
            canUseSyncedHabits: false,
          ),
        ),
        appConfigProvider.overrideWithValue(
          const AppConfig(
            environment: 'test',
            supabaseUrl: '',
            supabaseAnonKey: '',
            aiServiceBaseUrl: 'http://127.0.0.1:8000',
            useMockData: true,
          ),
        ),
        supabaseClientProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(quickCheckInStoreProvider),
      isA<GuestQuickCheckInDataSource>(),
    );
    final dashboard =
        await container.read(dashboardRepositoryProvider).getSnapshot();
    final insights =
        await container.read(insightsRepositoryProvider).getInsights();
    final calendar = await container
        .read(calendarIntegrationRepositoryProvider)
        .getIntegration();

    expect(dashboard.origin, DashboardOrigin.localDemo);
    expect(insights, isNotEmpty);
    expect(calendar.origin, CalendarIntegrationOrigin.localDemo);
  });
}
