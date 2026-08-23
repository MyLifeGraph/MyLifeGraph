import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/auth_providers.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';
import 'package:my_life_graph/core/network/api_failure.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/deadline_plans/domain/multi_exam_plan.dart';
import 'package:my_life_graph/features/deadline_plans/domain/multi_exam_plan_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/multi_exam_plan_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'same-principal profile and repository refresh preserve exact retry identity',
      () async {
    SharedPreferences.setMockInitialValues({});
    final auth = _MutableAuthController();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    auth.emit(_session(timezone: 'UTC', timezoneRevision: 1));

    final repositoryRevision = StateProvider<int>((_) => 0);
    final firstRepository = _SwitchingRepository(
      proposalResult: const ApiFailure(kind: ApiFailureKind.connection),
    );
    final refreshedRepository = _SwitchingRepository(
      proposalResult: MultiExamPlanNoChange(targetPlanId: multiExamTargetId),
    );
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((_) => auth),
        multiExamPlanRepositoryProvider.overrideWith(
          (ref) => ref.watch(repositoryRevision) == 0
              ? firstRepository
              : refreshedRepository,
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      multiExamPlanControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final original = container.read(multiExamPlanControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);

    const draft = MultiExamPlanProposalDraft(
      targetPlanId: multiExamTargetId,
      expectedPlanRevision: 1,
    );
    expect(await original.propose(draft), isFalse);
    expect(original.state.requiresExactRetry, isTrue);
    final requestId = firstRepository.requestIds.single;

    auth.emitError(StateError('profile refresh unavailable'));
    await Future<void>.delayed(Duration.zero);
    expect(
      identical(
        container.read(multiExamPlanControllerProvider.notifier),
        original,
      ),
      isTrue,
    );
    expect(original.state.requiresExactRetry, isTrue);

    auth.emit(_session(timezone: 'Europe/Berlin', timezoneRevision: 2));
    container.read(repositoryRevision.notifier).state = 1;
    await Future<void>.delayed(Duration.zero);

    final preserved = container.read(multiExamPlanControllerProvider.notifier);
    expect(identical(preserved, original), isTrue);
    expect(await preserved.retryExact(), isTrue);
    expect(refreshedRepository.requestIds, [requestId]);
    expect(
      identical(
        firstRepository.drafts.single,
        refreshedRepository.drafts.single,
      ),
      isTrue,
    );
    expect(preserved.state.requiresExactRetry, isFalse);
    expect(preserved.state.lastOutcome, 'no_change');
  });
}

AppSession _session({
  required String timezone,
  required int timezoneRevision,
}) =>
    AppSession.authenticated(
      AppProfile(
        id: '81000000-0000-4000-8000-000000000001',
        email: 'student@example.test',
        name: 'Student',
        timezone: timezone,
        role: AppRole.user,
        onboardingDone: true,
        authProvider: 'email',
        timezoneRevision: timezoneRevision,
      ),
    );

class _MutableAuthController extends AuthController {
  _MutableAuthController() : super(null);

  void emit(AppSession session) {
    state = AsyncValue.data(session);
  }

  void emitError(Object error) {
    state = AsyncValue.error(error, StackTrace.current);
  }
}

class _SwitchingRepository implements MultiExamPlanRepository {
  _SwitchingRepository({required this.proposalResult});

  final Object proposalResult;
  final List<String> requestIds = [];
  final List<MultiExamPlanProposalDraft> drafts = [];

  @override
  Future<MultiExamPlanFeed> getBalances() async =>
      MultiExamPlanFeed(balances: const []);

  @override
  Future<MultiExamPlanBatch> getBalance(String balanceId) =>
      throw UnimplementedError();

  @override
  Future<MultiExamPlanProposalResult> propose({
    required String requestId,
    required MultiExamPlanProposalDraft draft,
  }) async {
    requestIds.add(requestId);
    drafts.add(draft);
    final result = proposalResult;
    if (result is ApiFailure) throw result;
    return result as MultiExamPlanProposalResult;
  }

  @override
  Future<MultiExamPlanBatch> confirm({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  }) =>
      throw UnimplementedError();

  @override
  Future<MultiExamPlanBatch> cancel({
    required String balanceId,
    required String requestId,
    required int expectedRevision,
  }) =>
      throw UnimplementedError();
}
