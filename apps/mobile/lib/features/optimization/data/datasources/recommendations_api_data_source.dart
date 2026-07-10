import '../../../../core/network/api_client.dart';
import '../../domain/entities/recommendation.dart';
import '../../domain/entities/recommendation_feed.dart';

class RecommendationsApiDataSource {
  const RecommendationsApiDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<RecommendationFeed> getRecommendations({
    required String accessToken,
  }) async {
    final json = await _apiClient.getJson(
      '/v1/recommendations',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return RecommendationsApiResponse.fromJson(json).feed;
  }

  Future<RecommendationFeed> generateRecommendations({
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
    return RecommendationsApiResponse.fromJson(json).feed;
  }
}

class RecommendationsApiResponse {
  const RecommendationsApiResponse({required this.feed});

  factory RecommendationsApiResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException(
        'Recommendation response must contain an items list.',
      );
    }

    final needsGeneration = json['needs_generation'];
    if (needsGeneration is! bool) {
      throw const FormatException(
        'Recommendation response must contain needs_generation.',
      );
    }

    final periodKey = _readRequiredString(json['period_key'], 'period_key');
    final freshness = _parseFreshness(json['stale_reason']);
    if (needsGeneration != freshness.needsRefresh) {
      throw const FormatException(
        'Recommendation freshness does not match needs_generation.',
      );
    }

    final generatedAt = _readOptionalDateTime(
      json['generated_at'],
      'generated_at',
    );
    final items = rawItems.map((rawItem) {
      if (rawItem is! Map<String, dynamic>) {
        throw const FormatException(
          'Recommendation items must be JSON objects.',
        );
      }
      return RecommendationApiItem.fromJson(rawItem);
    }).toList(growable: false);

    return RecommendationsApiResponse(
      feed: RecommendationFeed(
        items: List.unmodifiable(items),
        provenance: RecommendationProvenance.authenticatedBackend,
        freshness: freshness,
        needsGeneration: needsGeneration,
        generatedAt: generatedAt,
        periodKey: periodKey,
      ),
    );
  }

  final RecommendationFeed feed;
}

class RecommendationApiItem {
  const RecommendationApiItem._();

  static Recommendation fromJson(Map<String, dynamic> json) {
    final category = _parseCategory(json['category']);
    if (category == null) {
      throw FormatException(
        'Unsupported recommendation category: ${json['category']}.',
      );
    }

    final id = _readRequiredString(json['id'], 'items[].id');
    final title = _readRequiredString(json['title'], 'items[].title');
    final reason = _readRequiredString(json['reason'], 'items[].reason');
    final actionLabel = _readRequiredString(
      json['action_label'],
      'items[].action_label',
    );
    final confidence = _readRequiredDouble(
      json['confidence'],
      'items[].confidence',
    );
    if (confidence < 0 || confidence > 1) {
      throw const FormatException(
        'Recommendation confidence must be between 0 and 1.',
      );
    }

    return Recommendation(
      id: id,
      title: title,
      reason: reason,
      actionLabel: actionLabel,
      category: category,
      confidence: confidence,
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
}

String _readRequiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Recommendation response has an invalid $field.');
  }
  return value.trim();
}

double _readRequiredDouble(Object? value, String field) {
  return switch (value) {
    int() => value.toDouble(),
    double() => value,
    _ => throw FormatException(
        'Recommendation response has an invalid $field.',
      ),
  };
}

DateTime? _readOptionalDateTime(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Recommendation response has an invalid $field.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Recommendation response has an invalid $field.');
  }
  return parsed;
}

RecommendationFreshness _parseFreshness(Object? value) {
  return switch (value) {
    null => RecommendationFreshness.current,
    'missing' => RecommendationFreshness.missing,
    'older_than_7_days' => RecommendationFreshness.olderThanSevenDays,
    'period_mismatch' => RecommendationFreshness.periodMismatch,
    _ => throw FormatException(
        'Unsupported recommendation stale_reason: $value.',
      ),
  };
}
