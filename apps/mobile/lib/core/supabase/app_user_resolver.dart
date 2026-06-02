import 'package:supabase_flutter/supabase_flutter.dart';

class AppUserResolver {
  const AppUserResolver(this._client);

  final SupabaseClient _client;

  Future<String> resolveUserId() async {
    final authUser = _client.auth.currentUser;
    if (authUser != null) {
      return authUser.id;
    }

    throw StateError('No authenticated Supabase user is available.');
  }
}
