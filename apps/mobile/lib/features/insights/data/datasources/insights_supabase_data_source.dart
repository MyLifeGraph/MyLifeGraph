import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../domain/entities/insight.dart';

class InsightsSupabaseDataSource {
  const InsightsSupabaseDataSource(
    this._client, {
    InsightSupabaseRowMapper mapper = const InsightSupabaseRowMapper(),
  }) : _mapper = mapper;

  final SupabaseClient _client;
  final InsightSupabaseRowMapper _mapper;

  Future<List<Insight>> getInsights() async {
    final userId = await AppUserResolver(_client).resolveUserId();
    final rows = await _client
        .from(SupabaseTables.aiInsights)
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(20);

    return List<Map<String, dynamic>>.from(rows as List)
        .map(_mapper.fromRow)
        .toList(growable: false);
  }
}

class InsightSupabaseRowMapper {
  const InsightSupabaseRowMapper();

  Insight fromRow(Map<String, dynamic> row) {
    final rawConfidence = row['confidence'];
    if (rawConfidence != null && rawConfidence is! num) {
      throw const FormatException(
        'Insight confidence must be numeric or null.',
      );
    }
    final confidence = (rawConfidence as num?)?.toDouble();
    if (confidence != null &&
        (!confidence.isFinite || confidence < 0 || confidence > 1)) {
      throw const FormatException(
        'Insight confidence must be between 0 and 1.',
      );
    }

    return Insight(
      id: row['id'] as String,
      title: row['title'] as String,
      summary: row['description'] as String,
      confidence: confidence,
      tags: [
        '${row['category']}'.toLowerCase(),
        '${row['priority']}'.toLowerCase(),
      ],
    );
  }
}

typedef InsightsPageFetcher = Future<Object?> Function(int from, int to);

class InsightsQueryPaginator {
  const InsightsQueryPaginator({
    this.pageSize = 500,
    this.maxRows = 10000,
  })  : assert(pageSize > 0),
        assert(maxRows > 0);

  final int pageSize;
  final int maxRows;

  Future<List<Map<String, dynamic>>> load(
    InsightsPageFetcher fetchPage,
  ) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0;;) {
      final remaining = maxRows - result.length;
      final requestedSize = remaining == 0
          ? 1
          : remaining < pageSize
              ? remaining
              : pageSize;
      final rows = await fetchPage(offset, offset + requestedSize - 1);
      final page = List<Map<String, dynamic>>.from(rows as List);
      if (page.length > requestedSize) {
        throw StateError('Insight source returned an oversized page.');
      }
      if (remaining == 0) {
        if (page.isEmpty) {
          return result;
        }
        throw StateError(
          'Insight source exceeds the $maxRows-row verification limit.',
        );
      }
      result.addAll(page);
      if (page.length < requestedSize) {
        return result;
      }
      offset += page.length;
    }
  }
}
