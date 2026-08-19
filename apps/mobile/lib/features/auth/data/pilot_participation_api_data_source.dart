import '../../../core/network/api_client.dart';
import '../domain/pilot_participation.dart';

abstract interface class PilotParticipationGateway {
  Future<PilotParticipationAcceptance> accept({
    required String accessToken,
  });
}

class PilotParticipationApiDataSource implements PilotParticipationGateway {
  const PilotParticipationApiDataSource(this._client);

  final ApiClient _client;

  @override
  Future<PilotParticipationAcceptance> accept({
    required String accessToken,
  }) async {
    final json = await _client.postJson(
      '/v1/account/pilot-participation',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: const {
        'contract_version': pilotParticipationContractVersion,
        'notice_version': pilotParticipationNoticeVersion,
        'confirmed_18_or_older': true,
      },
    );
    return PilotParticipationAcceptance.fromJson(json);
  }
}
