import '../../../../core/network/api_client.dart';
import '../../domain/entities/personal_patterns.dart';

class PersonalPatternsApiDataSource {
  const PersonalPatternsApiDataSource(this._client);

  final ApiClient _client;

  Future<PersonalPatterns> getPersonalPatterns({
    required String accessToken,
  }) async {
    final json = await _client.getJson(
      '/v1/insights/personal-patterns',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return PersonalPatterns.fromJson(json);
  }
}
