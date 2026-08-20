import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_life_graph/core/network/api_client.dart';
import 'package:my_life_graph/features/auth/data/pilot_participation_api_data_source.dart';
import 'package:my_life_graph/features/auth/domain/app_session.dart';
import 'package:my_life_graph/features/auth/domain/pilot_participation.dart';

void main() {
  test('participation response is strict and requires a UTC backend time', () {
    final acceptance = PilotParticipationAcceptance.fromJson({
      'contract_version': pilotParticipationContractVersion,
      'notice_version': pilotParticipationNoticeVersion,
      'accepted_at': '2026-08-19T12:00:00Z',
      'replayed': false,
    });

    expect(acceptance.acceptedAt.isUtc, isTrue);
    expect(acceptance.replayed, isFalse);
    expect(
      () => PilotParticipationAcceptance.fromJson({
        'contract_version': pilotParticipationContractVersion,
        'notice_version': pilotParticipationNoticeVersion,
        'accepted_at': '2026-08-19T12:00:00',
        'replayed': false,
      }),
      throwsA(isA<PilotParticipationContractException>()),
    );
  });

  test('API command sends only the versioned explicit self-attestation',
      () async {
    final client = _RecordingApiClient();
    final dataSource = PilotParticipationApiDataSource(client);

    await dataSource.accept(accessToken: 'verified-token');

    expect(client.path, '/v1/account/pilot-participation');
    expect(client.headers, {'Authorization': 'Bearer verified-token'});
    expect(client.body, {
      'contract_version': pilotParticipationContractVersion,
      'notice_version': pilotParticipationNoticeVersion,
      'confirmed_18_or_older': true,
    });
    expect(client.body, isNot(contains('birth_date')));
  });

  test('profile eligibility comes only from the persisted current pair', () {
    final accepted = _profile(
      noticeVersion: pilotParticipationNoticeVersion,
      acceptedAt: DateTime.utc(2026, 8, 19, 12),
    );
    final stale = _profile(
      noticeVersion: 'pilot-participation-notice-v0',
      acceptedAt: DateTime.utc(2026, 8, 19, 12),
    );

    expect(accepted.hasCurrentPilotParticipation, isTrue);
    expect(stale.hasCurrentPilotParticipation, isFalse);
    expect(_profile().hasCurrentPilotParticipation, isFalse);
  });
}

AppProfile _profile({String? noticeVersion, DateTime? acceptedAt}) {
  return AppProfile(
    id: 'profile-id',
    email: 'person@example.test',
    name: 'Person',
    timezone: 'Europe/Berlin',
    role: AppRole.user,
    onboardingDone: false,
    authProvider: 'email',
    pilotParticipationNoticeVersion: noticeVersion,
    pilotParticipationAcceptedAt: acceptedAt,
  );
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient() : super(Dio());

  String? path;
  Map<String, dynamic>? body;
  Map<String, String>? headers;

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    this.path = path;
    this.body = body;
    this.headers = headers;
    return {
      'contract_version': pilotParticipationContractVersion,
      'notice_version': pilotParticipationNoticeVersion,
      'accepted_at': '2026-08-19T12:00:00Z',
      'replayed': false,
    };
  }
}
