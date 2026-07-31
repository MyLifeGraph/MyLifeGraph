import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/application/profile_local_date_source.dart';
import 'package:my_life_graph/composition/auth_providers.dart';

final currentInstantProvider = Provider<CurrentInstantProvider>(
  (_) => DateTime.now,
);

final profileLocalDateSourceProvider = Provider<ProfileLocalDateSource>((ref) {
  return SessionProfileLocalDateSource(
    session: ref.watch(authControllerProvider).valueOrNull,
    currentInstant: ref.watch(currentInstantProvider),
  );
});
