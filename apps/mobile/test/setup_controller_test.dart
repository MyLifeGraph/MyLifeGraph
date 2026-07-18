import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_life_graph/core/navigation/app_routes.dart';
import 'package:my_life_graph/core/errors/app_exception.dart';
import 'package:my_life_graph/features/auth/data/intake_setup_repository.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/auth/domain/intake_response.dart';
import 'package:my_life_graph/features/auth/presentation/pages/onboarding_page.dart';
import 'package:my_life_graph/features/auth/presentation/providers/setup_providers.dart';

void main() {
  test('only first-time authenticated UTC setup requires confirmation', () {
    final utcAccount = AppSession.authenticated(
      const AppProfile(
        id: 'account',
        email: 'student@example.test',
        name: 'Student',
        timezone: 'UTC',
        role: AppRole.user,
        onboardingDone: false,
        authProvider: 'email',
      ),
    );
    final berlinAccount = AppSession.authenticated(
      utcAccount.profile.copyWith(timezone: 'Europe/Berlin'),
    );
    final utcGuest = AppSession.guest(
      utcAccount.profile.copyWith(role: AppRole.guest),
    );

    expect(
      shouldConfirmInitialUtcTimezone(editing: false, session: utcAccount),
      isTrue,
    );
    expect(
      shouldConfirmInitialUtcTimezone(editing: false, session: berlinAccount),
      isFalse,
    );
    expect(
      shouldConfirmInitialUtcTimezone(editing: false, session: utcGuest),
      isFalse,
    );
    expect(
      shouldConfirmInitialUtcTimezone(editing: true, session: utcAccount),
      isFalse,
    );
  });

  test('server failures remain exact-retry locked', () {
    expect(
      setupSaveRequiresExactRetry(
        _dioError(DioExceptionType.badResponse, statusCode: 503),
      ),
      isTrue,
    );
  });

  testWidgets('first authenticated UTC save requires an explicit choice',
      (tester) async {
    final gateway = _FakeSetupGateway(
      fetched: const IntakeSetupReadState.empty(),
    );
    late SetupController controller;
    final router = GoRouter(
      initialLocation: AppRoutes.onboarding,
      routes: [
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (_, __) => const OnboardingPage(),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (_, __) => const Scaffold(
            body: Text('Dashboard destination'),
          ),
        ),
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, __) => const Scaffold(
            body: Text('Settings destination'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          setupControllerProvider.overrideWith((ref) {
            controller = SetupController(
              repository: gateway,
              session: _authenticatedUtcSession(),
              onApplied: (_) {},
            );
            return controller;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    controller.updateDraft(_requiredDraft());
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Save setup'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save setup'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm account timezone'), findsOneWidget);
    expect(find.textContaining('currently uses UTC'), findsOneWidget);
    expect(find.text('Dashboard destination'), findsNothing);

    await tester.tap(find.text('Keep UTC'));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard destination'), findsOneWidget);
  });

  test('client validation error does not freeze the editable draft', () async {
    final gateway = _FakeSetupGateway(
      fetched: const IntakeSetupReadState.empty(),
    );
    final controller = SetupController(
      repository: gateway,
      session: _guestSession(onboardingDone: false),
      onApplied: (_) {},
    );
    addTearDown(controller.dispose);
    await _settleController();

    expect(await controller.save(), isFalse);
    expect(controller.state.retryLocked, isFalse);
    controller.updateDraft(_requiredDraft());
    expect(controller.state.draft?.hasRequiredAnswers, isTrue);
    expect(gateway.requests, isEmpty);
  });

  test('failed save retains draft and request id for an exact retry', () async {
    final gateway = _FakeSetupGateway(
      fetched: const IntakeSetupReadState.empty(),
      saveErrors: [_dioError(DioExceptionType.receiveTimeout)],
    );
    IntakeResponseDraft? applied;
    final controller = SetupController(
      repository: gateway,
      session: _guestSession(onboardingDone: false),
      onApplied: (responses) => applied = responses,
    );
    addTearDown(controller.dispose);
    await _settleController();
    final requestId = controller.state.requestId;
    final draft =
        _requiredDraft().copyWith(contextNote: 'Keep this exact note');
    controller.updateDraft(draft);

    expect(await controller.save(), isFalse);
    expect(controller.state.requestId, requestId);
    expect(controller.state.draft?.contextNote, 'Keep this exact note');
    expect(controller.state.saveError, isNotNull);
    expect(controller.state.retryLocked, isTrue);
    controller.updateDraft(
      draft.copyWith(contextNote: 'A changed payload must be ignored'),
    );
    expect(controller.state.draft?.contextNote, 'Keep this exact note');

    expect(await controller.save(), isTrue);
    expect(gateway.requests, hasLength(2));
    expect(gateway.requests[0].requestId, gateway.requests[1].requestId);
    expect(gateway.requests[0].baseRevision, 0);
    expect(gateway.requests[1].baseRevision, 0);
    expect(gateway.requests[1].toJson(), gateway.requests[0].toJson());
    expect(applied?.contextNote, 'Keep this exact note');
  });

  test('HTTP 422 keeps the draft editable for correction and retry', () async {
    final gateway = _FakeSetupGateway(
      fetched: const IntakeSetupReadState.empty(),
      saveErrors: [_dioError(DioExceptionType.badResponse, statusCode: 422)],
    );
    final controller = SetupController(
      repository: gateway,
      session: _guestSession(onboardingDone: false),
      onApplied: (_) {},
    );
    addTearDown(controller.dispose);
    await _settleController();
    final original = _requiredDraft().copyWith(contextNote: 'Needs fixing');
    controller.updateDraft(original);

    expect(await controller.save(), isFalse);
    expect(controller.state.retryLocked, isFalse);
    expect(controller.state.reloadSuggested, isFalse);

    final corrected = original.copyWith(contextNote: 'Corrected value');
    controller.updateDraft(corrected);
    expect(controller.state.draft?.contextNote, 'Corrected value');
    expect(await controller.save(), isTrue);
    expect(gateway.requests, hasLength(2));
    expect(gateway.requests.first.responses.contextNote, 'Needs fixing');
    expect(gateway.requests.last.responses.contextNote, 'Corrected value');
  });

  test('HTTP 409 stays editable and prompts a reload', () async {
    final gateway = _FakeSetupGateway(
      fetched: const IntakeSetupReadState.empty(),
      saveErrors: [_dioError(DioExceptionType.badResponse, statusCode: 409)],
    );
    final controller = SetupController(
      repository: gateway,
      session: _guestSession(onboardingDone: false),
      onApplied: (_) {},
    );
    addTearDown(controller.dispose);
    await _settleController();
    final original = _requiredDraft().copyWith(contextNote: 'Stale edit');
    controller.updateDraft(original);

    expect(await controller.save(), isFalse);
    expect(controller.state.retryLocked, isFalse);
    expect(controller.state.reloadSuggested, isTrue);

    controller.updateDraft(original.copyWith(contextNote: 'Still editable'));
    expect(controller.state.draft?.contextNote, 'Still editable');
    expect(controller.state.reloadSuggested, isTrue);
  });

  test('malformed save result locks the submitted payload for exact retry',
      () async {
    final gateway = _FakeSetupGateway(
      fetched: const IntakeSetupReadState.empty(),
      saveResults: const [IntakeSetupReadState.empty()],
    );
    final controller = SetupController(
      repository: gateway,
      session: _guestSession(onboardingDone: false),
      onApplied: (_) {},
    );
    addTearDown(controller.dispose);
    await _settleController();
    final submitted = _requiredDraft().copyWith(contextNote: 'Exact payload');
    controller.updateDraft(submitted);

    expect(await controller.save(), isFalse);
    expect(controller.state.retryLocked, isTrue);
    controller.updateDraft(submitted.copyWith(contextNote: 'Ignored edit'));
    expect(controller.state.draft?.contextNote, 'Exact payload');
  });

  test('pending setup locks edits and resumes exact request and base revision',
      () async {
    const pendingRequestId = '250028f2-9a68-425a-a7d3-3a65dcaa3be5';
    final pendingDraft = _requiredDraft().copyWith(
      contextNote: 'Pending exact content',
    );
    final gateway = _FakeSetupGateway(
      fetched: IntakeSetupReadState(
        exists: true,
        revision: 4,
        baseRevision: 3,
        requestId: pendingRequestId,
        status: 'pending',
        intakeResponseId: null,
        snapshotId: null,
        completedAt: null,
        responses: pendingDraft,
        summary: const {},
      ),
    );
    final controller = SetupController(
      repository: gateway,
      session: _guestSession(onboardingDone: false),
      onApplied: (_) {},
    );
    addTearDown(controller.dispose);
    await _settleController();

    expect(controller.state.isPending, isTrue);
    expect(controller.state.requestId, pendingRequestId);
    controller.updateDraft(
      pendingDraft.copyWith(contextNote: 'This edit must be ignored'),
    );
    expect(controller.state.draft?.contextNote, 'Pending exact content');

    expect(await controller.save(), isTrue);
    expect(gateway.requests.single.requestId, pendingRequestId);
    expect(gateway.requests.single.baseRevision, 3);
    expect(
      gateway.requests.single.responses.contextNote,
      'Pending exact content',
    );
  });
}

Future<void> _settleController() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeSetupGateway implements IntakeSetupGateway {
  _FakeSetupGateway({
    required this.fetched,
    this.saveErrors = const [],
    this.saveResults = const [],
  });

  final IntakeSetupReadState fetched;
  final List<Object> saveErrors;
  final List<IntakeSetupReadState> saveResults;
  final List<IntakeSetupSaveRequest> requests = [];

  @override
  Future<IntakeSetupReadState> fetch(AppSession session) async => fetched;

  @override
  Future<IntakeSetupReadState> save(
    AppSession session,
    IntakeSetupSaveRequest request,
  ) async {
    requests.add(request);
    final attempt = requests.length - 1;
    if (attempt < saveErrors.length) {
      throw saveErrors[attempt];
    }
    final resultAttempt = attempt - saveErrors.length;
    if (resultAttempt >= 0 && resultAttempt < saveResults.length) {
      return saveResults[resultAttempt];
    }
    return IntakeSetupReadState(
      exists: true,
      revision: request.baseRevision + 1,
      baseRevision: request.baseRevision,
      requestId: request.requestId,
      status: 'applied',
      intakeResponseId: 'intake',
      snapshotId: 'snapshot',
      completedAt: DateTime.utc(2026, 7, 10),
      responses: request.responses,
      summary: const {},
    );
  }
}

AppException _dioError(DioExceptionType type, {int? statusCode}) {
  final request = RequestOptions(path: '/v1/intake/complete');
  return AppException(
    'Network request failed',
    cause: DioException(
      requestOptions: request,
      type: type,
      response: statusCode == null
          ? null
          : Response<void>(requestOptions: request, statusCode: statusCode),
    ),
  );
}

AppSession _guestSession({required bool onboardingDone}) {
  return AppSession.guest(
    AppProfile(
      id: 'local_guest',
      email: 'guest@personal-coach.local',
      name: 'Guest Coach User',
      timezone: 'Europe/Berlin',
      role: AppRole.guest,
      onboardingDone: onboardingDone,
      authProvider: 'guest',
    ),
  );
}

AppSession _authenticatedUtcSession() {
  return AppSession.authenticated(
    const AppProfile(
      id: 'account-id',
      email: 'student@example.test',
      name: 'Student',
      timezone: 'UTC',
      role: AppRole.user,
      onboardingDone: false,
      authProvider: 'email',
    ),
  );
}

IntakeResponseDraft _requiredDraft() {
  return const IntakeResponseDraft(
    displayName: null,
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
