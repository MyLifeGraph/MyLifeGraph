import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/coach/data/coach_credential_store.dart';

final coachCredentialStoreProvider = Provider<CoachCredentialStore>(
  (_) => PlatformCoachCredentialStore(),
);
