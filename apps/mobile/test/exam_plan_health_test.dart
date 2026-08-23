import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/composition/deadline_plan_providers.dart';
import 'package:my_life_graph/core/capabilities/app_surface_capabilities.dart';
import 'package:my_life_graph/core/config/app_config.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/core/utils/local_date.dart';
import 'package:my_life_graph/features/deadline_plans/data/exam_plan_health_api_data_source.dart';
import 'package:my_life_graph/features/deadline_plans/data/exam_plan_health_repository_impl.dart';
import 'package:my_life_graph/features/deadline_plans/domain/deadline_plan.dart';
import 'package:my_life_graph/features/deadline_plans/domain/exam_plan_health.dart';

void main() {
  test('strict response preserves status arithmetic and stable priority', () {
    final response = ExamPlanHealth.fromJson(_healthEnvelope());

    expect(response.exams, hasLength(2));
    expect(response.exams.first.status, ExamPlanHealthStatus.yellow);
    expect(response.exams.first.reserveMinutes, 90);
    expect(response.needsAttention, hasLength(1));

    final reordered = _healthEnvelope();
    reordered['exams'] = (reordered['exams'] as List).reversed.toList();
    expect(
      () => ExamPlanHealth.fromJson(reordered),
      throwsA(isA<ExamPlanHealthContractException>()),
    );
  });

  test('strict item rejects false green and partial Unknown capacity', () {
    final falseGreen = _healthEnvelope();
    final first = ((falseGreen['exams'] as List).first as Map<String, dynamic>);
    first
      ..['status'] = 'green'
      ..['reasons'] = <String>[];
    expect(
      () => ExamPlanHealth.fromJson(falseGreen),
      throwsA(isA<ExamPlanHealthContractException>()),
    );

    final unknown = _healthEnvelope();
    final item = ((unknown['exams'] as List).first as Map<String, dynamic>);
    item
      ..['status'] = 'unknown'
      ..['available_replan_capacity_minutes'] = null
      ..['reserve_minutes'] = null
      ..['reserve_full_sessions'] = null
      ..['latest_safe_start_on'] = '2026-08-20'
      ..['recommended_start_on'] = null
      ..['recommended_start_reason'] = 'Calendar authority is incomplete.'
      ..['reasons'] = <String>['calendar_import_unavailable']
      ..['missing_sources'] = <String>['calendar_import'];
    expect(
      () => ExamPlanHealth.fromJson(unknown),
      throwsA(isA<ExamPlanHealthContractException>()),
    );
  });

  test('completed overdue Exam keeps green noncontradictory civil dates', () {
    final response = _healthEnvelope();
    final first = (response['exams'] as List).first as Map<String, dynamic>;
    first
      ..['deadline_at'] = '2026-08-10T18:00:00Z'
      ..['local_deadline_date'] = '2026-08-10'
      ..['status'] = 'green'
      ..['remaining_minutes'] = 0
      ..['sessions_needed'] = 0
      ..['future_reserved_minutes'] = 0
      ..['minutes_to_schedule'] = 0
      ..['reserve_minutes'] = first['available_replan_capacity_minutes']
      ..['reserve_full_sessions'] =
          (first['available_replan_capacity_minutes'] as int) ~/ 50
      ..['latest_safe_start_on'] = '2026-08-13'
      ..['recommended_start_on'] = '2026-08-13'
      ..['reasons'] = <String>[];

    final parsed = ExamPlanHealth.fromJson(response).exams.first;
    expect(parsed.status, ExamPlanHealthStatus.green);
    expect(parsed.latestSafeStartOn, '2026-08-13');
    expect(parsed.recommendedStartOn, '2026-08-13');

    first['latest_safe_start_on'] = '2026-08-10';
    expect(
      () => ExamPlanHealth.fromJson(response),
      throwsA(isA<ExamPlanHealthContractException>()),
    );
  });

  test('profile IANA timezone owns local dates across DST', () {
    final invalidZone = _healthEnvelope()..['timezone'] = 'Europe/Not_A_Zone';
    expect(
      () => ExamPlanHealth.fromJson(invalidZone),
      throwsA(isA<ExamPlanHealthContractException>()),
    );

    final wrongLocalDate = _healthEnvelope()
      ..['timezone'] = 'Europe/Berlin'
      ..['local_date'] = '2026-08-12';
    expect(
      () => ExamPlanHealth.fromJson(wrongLocalDate),
      throwsA(isA<ExamPlanHealthContractException>()),
    );

    final wrongDeadlineDate = _healthEnvelope();
    ((wrongDeadlineDate['exams'] as List).first
        as Map<String, dynamic>)['local_deadline_date'] = '2026-08-29';
    expect(
      () => ExamPlanHealth.fromJson(wrongDeadlineDate),
      throwsA(isA<ExamPlanHealthContractException>()),
    );

    expect(
      civilDateDifferenceInDays('2026-03-30', '2026-03-23'),
      7,
    );
  });

  test('preview uses its own endpoint and exact editor fingerprint', () async {
    final client = _TrackingApiClient(
      getResponse: _healthEnvelope(),
      postResponse: _previewEnvelope(),
    );
    final repository = _repository(client);
    final draft = _previewDraft();

    await repository.getHealth();
    final preview = await repository.preview(draft);

    expect(client.getCalls, ['/v1/deadline-plans/exam-plan-health']);
    expect(client.postCalls, ['/v1/deadline-plans/exam-plan-health/preview']);
    expect(preview.exam.title, 'Physics');
    expect(client.postBody, {
      'contract_version': examPlanHealthContractVersion,
      'plan_id': '11111111-1111-4111-8111-111111111111',
      'base_revision': 1,
      'kind': 'exam',
      'title': 'Physics',
      'deadline_at': '2026-09-20T18:00:00.000Z',
      'estimated_total_minutes': 420,
      'credited_prior_minutes': 20,
      'preferred_session_minutes': 50,
      'max_daily_minutes': 120,
      'planning_start_on': '2026-08-14',
      'buffer_days': 2,
      'source_kind': 'calendar_event',
      'source_calendar_event_id': '22222222-2222-4222-8222-222222222222',
      'source_calendar_event_fingerprint':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'use_calendar_availability': true,
    });
    expect(client.headers, {'Authorization': 'Bearer account-token'});
  });

  test('proposal preview identity comes only from an active source plan', () {
    final proposal = DeadlinePlanProposalDraft(
      planId: '11111111-1111-4111-8111-111111111111',
      baseRevision: 1,
      kind: DeadlinePlanKind.exam,
      title: 'Physics',
      deadlineAt: DateTime.parse('2026-09-20T18:00:00Z'),
      estimatedTotalMinutes: 420,
      creditedPriorMinutes: 20,
      preferredSessionMinutes: 50,
      maxDailyMinutes: 120,
      planningStartOn: '2026-08-14',
      bufferDays: 2,
      sourceKind: DeadlinePlanSourceKind.manual,
      sourceCalendarEventId: null,
      sourceCalendarEventFingerprint: null,
      useCalendarAvailability: false,
    );

    final draftSimulation = ExamPlanHealthPreviewDraft.fromProposal(proposal);
    expect(draftSimulation.planId, isNull);
    expect(draftSimulation.baseRevision, isNull);

    final activeReplan = ExamPlanHealthPreviewDraft.fromProposal(
      proposal,
      activePlanId: proposal.planId,
      activeBaseRevision: proposal.baseRevision,
    );
    expect(activeReplan.planId, proposal.planId);
    expect(activeReplan.baseRevision, proposal.baseRevision);

    expect(
      () => ExamPlanHealthPreviewDraft.fromProposal(
        proposal,
        activePlanId: '33333333-3333-4333-8333-333333333333',
        activeBaseRevision: 1,
      ),
      throwsA(isA<ExamPlanHealthContractException>()),
    );
  });

  test('guest and mock guards perform zero authenticated product calls',
      () async {
    final client = _TrackingApiClient(
      getResponse: _healthEnvelope(),
      postResponse: _previewEnvelope(),
    );
    final repository = _repository(client, canUseSyncedPlanner: false);

    await expectLater(
      repository.getHealth(),
      throwsA(isA<ExamPlanHealthContractException>()),
    );
    await expectLater(
      repository.preview(_previewDraft()),
      throwsA(isA<ExamPlanHealthContractException>()),
    );
    expect(client.totalCalls, 0);

    var repositoryReads = 0;
    final container = ProviderContainer(
      overrides: [
        appSurfaceCapabilitiesProvider.overrideWithValue(
          const AppSurfaceCapabilities(
            isLocalDemo: true,
            canUseSyncedHabits: false,
          ),
        ),
        examPlanHealthRepositoryProvider.overrideWith((ref) {
          repositoryReads += 1;
          return repository;
        }),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(examPlanHealthProvider.future), isNull);
    expect(repositoryReads, 0);
    expect(client.totalCalls, 0);
  });
}

Map<String, dynamic> _healthEnvelope() => {
      'contract_version': examPlanHealthContractVersion,
      'origin': 'authenticated_backend',
      'generated_at': '2026-08-13T08:00:00Z',
      'timezone': 'UTC',
      'local_date': '2026-08-13',
      'exams': [
        _item(
          planId: '11111111-1111-4111-8111-111111111111',
          title: 'Analysis',
          deadline: '2026-08-30T18:00:00Z',
          status: 'yellow',
          reasons: const ['low_session_reserve'],
          remaining: 300,
          capacity: 390,
        ),
        _item(
          planId: '33333333-3333-4333-8333-333333333333',
          title: 'Physics',
          deadline: '2026-09-20T18:00:00Z',
          status: 'green',
          reasons: const [],
          remaining: 200,
          capacity: 600,
        ),
      ],
    };

Map<String, dynamic> _previewEnvelope() => {
      'contract_version': examPlanHealthContractVersion,
      'origin': 'authenticated_backend_preview',
      'generated_at': '2026-08-13T08:00:00Z',
      'timezone': 'UTC',
      'local_date': '2026-08-13',
      'exam': _item(
        planId: '11111111-1111-4111-8111-111111111111',
        title: 'Physics',
        deadline: '2026-09-20T18:00:00Z',
        status: 'green',
        reasons: const [],
        remaining: 400,
        capacity: 700,
      ),
    };

Map<String, dynamic> _item({
  required String planId,
  required String title,
  required String deadline,
  required String status,
  required List<String> reasons,
  required int remaining,
  required int capacity,
}) =>
    {
      'plan_id': planId,
      'title': title,
      'deadline_at': deadline,
      'local_deadline_date': deadline.substring(0, 10),
      'status': status,
      'remaining_minutes': remaining,
      'preferred_session_minutes': 50,
      'sessions_needed': (remaining / 50).ceil(),
      'future_reserved_minutes': 0,
      'minutes_to_schedule': remaining,
      'available_replan_capacity_minutes': capacity,
      'reserve_minutes': capacity - remaining,
      'reserve_full_sessions': (capacity - remaining) ~/ 50,
      'latest_safe_start_on': '2026-08-22',
      'recommended_start_on': '2026-08-14',
      'recommended_start_reason': null,
      'reasons': reasons,
      'missing_sources': <String>[],
    };

ExamPlanHealthPreviewDraft _previewDraft() => ExamPlanHealthPreviewDraft(
      planId: '11111111-1111-4111-8111-111111111111',
      baseRevision: 1,
      title: 'Physics',
      deadlineAt: DateTime.parse('2026-09-20T18:00:00Z'),
      estimatedTotalMinutes: 420,
      creditedPriorMinutes: 20,
      preferredSessionMinutes: 50,
      maxDailyMinutes: 120,
      planningStartOn: '2026-08-14',
      bufferDays: 2,
      sourceKind: DeadlinePlanSourceKind.calendarEvent,
      sourceCalendarEventId: '22222222-2222-4222-8222-222222222222',
      sourceCalendarEventFingerprint:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      useCalendarAvailability: true,
    );

ExamPlanHealthRepositoryImpl _repository(
  _TrackingApiClient client, {
  bool canUseSyncedPlanner = true,
}) =>
    ExamPlanHealthRepositoryImpl(
      config: const AppConfig(
        environment: 'test',
        supabaseUrl: 'https://example.supabase.co',
        supabaseAnonKey: 'anon-shape-only',
        aiServiceBaseUrl: 'http://127.0.0.1:8000',
        useMockData: false,
      ),
      apiDataSource: ExamPlanHealthApiDataSource(client),
      accessTokenProvider: () => 'account-token',
      canUseSyncedPlanner: canUseSyncedPlanner,
    );

class _TrackingApiClient extends ApiClient {
  _TrackingApiClient({required this.getResponse, required this.postResponse})
      : super(Dio());

  final Map<String, dynamic> getResponse;
  final Map<String, dynamic> postResponse;
  final List<String> getCalls = [];
  final List<String> postCalls = [];
  Map<String, dynamic>? postBody;
  Map<String, String>? headers;

  int get totalCalls => getCalls.length + postCalls.length;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    getCalls.add(path);
    this.headers = headers;
    return getResponse;
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    postCalls.add(path);
    postBody = body;
    this.headers = headers;
    return postResponse;
  }
}
