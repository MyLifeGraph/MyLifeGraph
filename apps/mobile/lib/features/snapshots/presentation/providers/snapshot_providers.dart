import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/capabilities/app_surface_capabilities.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/supabase/supabase_providers.dart';
import '../../application/snapshot_refresh_service.dart';
import '../../data/snapshot_api_data_source.dart';

final snapshotApiDataSourceProvider = Provider<SnapshotApiDataSource>(
  (ref) => SnapshotApiDataSource(ref.watch(apiClientProvider)),
);

final snapshotAccessTokenProvider = Provider<SnapshotAccessTokenProvider>(
  (ref) {
    return () =>
        ref.read(supabaseClientProvider)?.auth.currentSession?.accessToken;
  },
);

final snapshotRefreshServiceProvider = Provider<SnapshotRefreshService>(
  (ref) => SnapshotRefreshService(
    config: ref.watch(appConfigProvider),
    apiDataSource: ref.watch(snapshotApiDataSourceProvider),
    accessTokenProvider: ref.watch(snapshotAccessTokenProvider),
    allowRemoteRefresh: !ref.watch(appSurfaceCapabilitiesProvider).isLocalDemo,
  ),
);
