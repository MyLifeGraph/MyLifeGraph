import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../features/settings/data/account_api_data_source.dart';
import '../features/settings/data/account_deletion_coordinator.dart';
import '../features/settings/data/account_deletion_pending_store.dart';

final accountApiDataSourceProvider = Provider<AccountApiDataSource>(
  (ref) => AccountApiDataSource(ref.watch(apiClientProvider)),
);

final accountDeletionPendingStoreProvider =
    Provider<AccountDeletionPendingStore>(
  (_) => const AccountDeletionPendingStore(),
);

final accountDeletionCoordinatorProvider = Provider<AccountDeletionCoordinator>(
  (ref) => AccountDeletionCoordinator(
    apiDataSource: ref.watch(accountApiDataSourceProvider),
    pendingStore: ref.watch(accountDeletionPendingStoreProvider),
  ),
);
