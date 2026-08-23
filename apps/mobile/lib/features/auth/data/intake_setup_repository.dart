import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_session.dart';
import '../domain/intake_response.dart';
import 'guest_setup_data_source.dart';
import 'intake_api_data_source.dart';

abstract interface class IntakeSetupGateway {
  Future<IntakeSetupReadState> fetch(AppSession session);

  Future<IntakeSetupReadState> save(
    AppSession session,
    IntakeSetupSaveRequest request,
  );
}

class IntakeSetupRepository implements IntakeSetupGateway {
  const IntakeSetupRepository({
    required IntakeApiDataSource apiDataSource,
    required GuestSetupDataSource guestDataSource,
    required SupabaseClient? supabaseClient,
    required bool useMockData,
  })  : _apiDataSource = apiDataSource,
        _guestDataSource = guestDataSource,
        _supabaseClient = supabaseClient,
        _useMockData = useMockData;

  final IntakeApiDataSource _apiDataSource;
  final GuestSetupDataSource _guestDataSource;
  final SupabaseClient? _supabaseClient;
  final bool _useMockData;

  @override
  Future<IntakeSetupReadState> fetch(AppSession session) async {
    if (_usesLocalSetup(session)) {
      return _guestDataSource.read();
    }
    return _apiDataSource.fetchSetup(accessToken: _accessToken());
  }

  @override
  Future<IntakeSetupReadState> save(
    AppSession session,
    IntakeSetupSaveRequest request,
  ) async {
    if (_usesLocalSetup(session)) {
      return _guestDataSource.save(request);
    }
    return _apiDataSource.completeIntake(
      accessToken: _accessToken(),
      request: request,
    );
  }

  String _accessToken() {
    final token = _supabaseClient?.auth.currentSession?.accessToken.trim();
    if (token == null || token.isEmpty) {
      throw StateError('An authenticated session is required for setup.');
    }
    return token;
  }

  bool _usesLocalSetup(AppSession session) =>
      _useMockData ||
      session.isGuestSession ||
      session.profile.authProvider == 'guest' ||
      session.profile.email.toLowerCase() == 'demo@personal-coach.local';
}
