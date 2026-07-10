import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/auth/data/guest_setup_data_source.dart';
import 'package:my_life_graph/features/auth/data/intake_api_data_source.dart';
import 'package:my_life_graph/features/auth/data/intake_setup_repository.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/auth/domain/intake_response.dart';

void main() {
  test('mock config keeps authenticated setup entirely in guest store',
      () async {
    final api = _TrackingIntakeApiDataSource();
    final guest = _TrackingGuestSetupDataSource();
    final repository = IntakeSetupRepository(
      apiDataSource: api,
      guestDataSource: guest,
      supabaseClient: null,
      useMockData: true,
    );
    final session = AppSession.authenticated(_profile());
    final request = IntakeSetupSaveRequest(
      requestId: 'f86a55da-c243-43f6-8b56-dce9c1fdb378',
      baseRevision: 0,
      responses: _requiredDraft(),
    );

    final fetched = await repository.fetch(session);
    final saved = await repository.save(session, request);

    expect(fetched.exists, isFalse);
    expect(saved.status, 'applied');
    expect(guest.readCalls, 1);
    expect(guest.saveCalls, 1);
    expect(api.fetchCalls, 0);
    expect(api.saveCalls, 0);
  });
}

class _TrackingIntakeApiDataSource extends IntakeApiDataSource {
  _TrackingIntakeApiDataSource() : super(ApiClient(Dio()));

  int fetchCalls = 0;
  int saveCalls = 0;

  @override
  Future<IntakeSetupReadState> fetchSetup({
    required String accessToken,
  }) async {
    fetchCalls += 1;
    throw StateError('The network path must not be used in mock mode.');
  }

  @override
  Future<IntakeSetupReadState> completeIntake({
    required String accessToken,
    required IntakeSetupSaveRequest request,
  }) async {
    saveCalls += 1;
    throw StateError('The network path must not be used in mock mode.');
  }
}

class _TrackingGuestSetupDataSource extends GuestSetupDataSource {
  int readCalls = 0;
  int saveCalls = 0;

  @override
  Future<IntakeSetupReadState> read() async {
    readCalls += 1;
    return const IntakeSetupReadState.empty();
  }

  @override
  Future<IntakeSetupReadState> save(IntakeSetupSaveRequest request) async {
    saveCalls += 1;
    return IntakeSetupReadState(
      exists: true,
      revision: 1,
      baseRevision: request.baseRevision,
      requestId: request.requestId,
      status: 'applied',
      intakeResponseId: 'local-intake',
      snapshotId: 'local-snapshot',
      completedAt: DateTime.utc(2026, 7, 10),
      responses: request.responses,
      summary: const {},
    );
  }
}

AppProfile _profile() {
  return const AppProfile(
    id: 'account-id',
    email: 'real@example.test',
    name: 'Mock Account',
    timezone: 'Europe/Berlin',
    role: AppRole.user,
    onboardingDone: false,
    authProvider: 'email',
  );
}

IntakeResponseDraft _requiredDraft() {
  return const IntakeResponseDraft(
    displayName: 'Mock Account',
    primaryFocusAreas: ['focus'],
    goals: [],
    frictionPoints: [],
    weekdayShape: 'flexible',
    bestEnergyWindow: 'morning',
    coachingStyle: 'direct',
    reminderPreference: IntakeReminderPreference(enabled: false),
    routines: [],
    fixedCommitments: [],
    contextNote: null,
    calendarConnectionIntent: null,
  );
}
