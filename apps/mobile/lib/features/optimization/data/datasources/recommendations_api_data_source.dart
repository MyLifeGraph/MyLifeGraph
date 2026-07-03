import '../../../../core/network/api_client.dart';
import '../../domain/entities/recommendation.dart';

class RecommendationsApiDataSource {
  const RecommendationsApiDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Recommendation>> getRecommendations({
    required String accessToken,
  }) async {
    final json = await _apiClient.getJson(
      '/v1/recommendations',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return RecommendationsApiResponse.fromJson(json).recommendations;
  }

  Future<List<Recommendation>> generateRecommendations({
    required String accessToken,
    int windowDays = 28,
    bool force = false,
  }) async {
    final json = await _apiClient.postJson(
      '/v1/recommendations/generate',
      body: {
        'window_days': windowDays,
        'force': force,
        'allow_llm_wording': false,
      },
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return RecommendationsApiResponse.fromJson(json).recommendations;
  }
}

class RecommendationsApiResponse {
  const RecommendationsApiResponse({required this.recommendations});

  factory RecommendationsApiResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      return const RecommendationsApiResponse(recommendations: []);
    }

    return RecommendationsApiResponse(
      recommendations: rawItems
          .whereType<Map<String, dynamic>>()
          .map(RecommendationApiItem.fromJson)
          .nonNulls
          .toList(growable: false),
    );
  }

  final List<Recommendation> recommendations;
}

class RecommendationApiItem {
  const RecommendationApiItem._();

  static Recommendation? fromJson(Map<String, dynamic> json) {
    final category = _parseCategory(json['category']);
    if (category == null) {
      return null;
    }

    final id = _readString(json['id']);
    final title = _readString(json['title']);
    final reason = _readString(json['reason']);
    final actionLabel = _readString(json['action_label']);
    if (id == null || title == null || reason == null || actionLabel == null) {
      return null;
    }

    return Recommendation(
      id: id,
      title: title,
      reason: reason,
      actionLabel: actionLabel,
      category: category,
      confidence: _readDouble(json['confidence']) ?? 0,
    );
  }

  static RecommendationCategory? _parseCategory(Object? value) {
    return switch (value) {
      'focus' => RecommendationCategory.focus,
      'recovery' => RecommendationCategory.recovery,
      'movement' => RecommendationCategory.movement,
      'planning' => RecommendationCategory.planning,
      _ => null,
    };
  }

  static String? _readString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return value;
  }

  static double? _readDouble(Object? value) {
    return switch (value) {
      int() => value.toDouble(),
      double() => value,
      _ => null,
    };
  }
}
