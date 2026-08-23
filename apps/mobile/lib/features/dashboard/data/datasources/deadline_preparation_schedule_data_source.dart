import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/app_user_resolver.dart';
import '../../../../core/supabase/supabase_tables.dart';
import '../../domain/entities/deadline_preparation_schedule_block.dart';

const maxDashboardPreparationBlocks = 240;
const maxDashboardPreparationPlans = 50;

abstract interface class DeadlinePreparationScheduleDataSource {
  Future<List<DeadlinePreparationScheduleBlock>> getActiveBlocksForWeek({
    required DateTime startDate,
    required DateTime endDate,
  });
}

class DeadlinePreparationScheduleSupabaseDataSource
    implements DeadlinePreparationScheduleDataSource {
  const DeadlinePreparationScheduleSupabaseDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<DeadlinePreparationScheduleBlock>> getActiveBlocksForWeek({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final range = DeadlinePreparationScheduleRange(
      startDate: startDate,
      endDate: endDate,
    );
    final userId = await AppUserResolver(_client).resolveUserId();
    final blockResponse = await _client
        .from(SupabaseTables.deadlinePlanBlocks)
        .select(
          'id,plan_id,revision,sequence,reservation_state,starts_at,ends_at,'
          'planned_minutes',
        )
        .eq('user_id', userId)
        .eq('reservation_state', 'active')
        .gte('starts_at', range.expandedUtcStart.toIso8601String())
        .lt('starts_at', range.expandedUtcEndExclusive.toIso8601String())
        .order('starts_at', ascending: true)
        .order('id', ascending: true)
        .limit(maxDashboardPreparationBlocks + 1);
    final blockRows = _rows(blockResponse, 'preparation blocks');
    if (blockRows.length > maxDashboardPreparationBlocks) {
      throw const DeadlinePreparationScheduleException(
        'Preparation block result exceeded its bounded size.',
      );
    }

    final planIds = DeadlinePreparationScheduleMapper.activePlanIds(blockRows);
    if (planIds.isEmpty) return const [];
    if (planIds.length > maxDashboardPreparationPlans) {
      throw const DeadlinePreparationScheduleException(
        'Preparation plan result exceeded its bounded size.',
      );
    }

    final planResponse = await _client
        .from(SupabaseTables.deadlinePlans)
        .select('id,title,status,current_revision')
        .eq('user_id', userId)
        .eq('status', 'active')
        .inFilter('id', planIds.toList(growable: false))
        .order('id', ascending: true)
        .limit(maxDashboardPreparationPlans + 1);
    final planRows = _rows(planResponse, 'preparation plans');
    return const DeadlinePreparationScheduleMapper().map(
      blockRows: blockRows,
      planRows: planRows,
    );
  }

  List<Map<String, dynamic>> _rows(Object? value, String label) {
    if (value is! List) {
      throw DeadlinePreparationScheduleException('$label are invalid.');
    }
    try {
      return value
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
    } catch (_) {
      throw DeadlinePreparationScheduleException('$label are invalid.');
    }
  }
}

class DeadlinePreparationScheduleRange {
  DeadlinePreparationScheduleRange({
    required DateTime startDate,
    required DateTime endDate,
  })  : startDate = DateTime(startDate.year, startDate.month, startDate.day),
        endDate = DateTime(endDate.year, endDate.month, endDate.day) {
    final days = this.endDate.difference(this.startDate).inDays;
    if (days < 0 || days > 6) {
      throw const DeadlinePreparationScheduleException(
        'Preparation schedule range must be one displayed week.',
      );
    }
  }

  final DateTime startDate;
  final DateTime endDate;

  String get startKey => _dateKey(startDate);
  String get endKey => _dateKey(endDate);

  DateTime get expandedUtcStart =>
      DateTime.utc(startDate.year, startDate.month, startDate.day)
          .subtract(const Duration(days: 1));

  DateTime get expandedUtcEndExclusive =>
      DateTime.utc(endDate.year, endDate.month, endDate.day)
          .add(const Duration(days: 2));
}

class DeadlinePreparationScheduleMapper {
  const DeadlinePreparationScheduleMapper();

  static Set<String> activePlanIds(List<Map<String, dynamic>> blockRows) {
    if (blockRows.length > maxDashboardPreparationBlocks) {
      throw const DeadlinePreparationScheduleException(
        'Preparation block result exceeded its bounded size.',
      );
    }
    final ids = <String>{};
    for (final row in blockRows) {
      final state = row['reservation_state'];
      if (!_reservationStates.contains(state)) {
        throw const DeadlinePreparationScheduleException(
          'Preparation block state is invalid.',
        );
      }
      if (state != 'active') continue;
      ids.add(_uuid(row['plan_id'], 'Preparation plan identity'));
    }
    return ids;
  }

  List<DeadlinePreparationScheduleBlock> map({
    required List<Map<String, dynamic>> blockRows,
    required List<Map<String, dynamic>> planRows,
  }) {
    if (blockRows.length > maxDashboardPreparationBlocks ||
        planRows.length > maxDashboardPreparationPlans) {
      throw const DeadlinePreparationScheduleException(
        'Preparation schedule result exceeded its bounded size.',
      );
    }

    final activePlans = <String, _ActivePlanProjection>{};
    final seenPlanRows = <String>{};
    for (final row in planRows) {
      final id = _uuid(row['id'], 'Preparation plan identity');
      if (!seenPlanRows.add(id)) {
        throw const DeadlinePreparationScheduleException(
          'Preparation plan result contains duplicates.',
        );
      }
      final status = row['status'];
      if (!_planStatuses.contains(status)) {
        throw const DeadlinePreparationScheduleException(
          'Preparation plan status is invalid.',
        );
      }
      if (status != 'active') continue;
      final title = row['title'];
      final revision = row['current_revision'];
      if (title is! String ||
          title.trim() != title ||
          title.isEmpty ||
          title.runes.length > 160 ||
          revision is! int ||
          revision < 1 ||
          revision > 200) {
        throw const DeadlinePreparationScheduleException(
          'Active preparation plan projection is invalid.',
        );
      }
      activePlans[id] = _ActivePlanProjection(title, revision);
    }

    final result = <DeadlinePreparationScheduleBlock>[];
    final seenBlockIds = <String>{};
    final seenSequences = <String>{};
    for (final row in blockRows) {
      final state = row['reservation_state'];
      if (!_reservationStates.contains(state)) {
        throw const DeadlinePreparationScheduleException(
          'Preparation block state is invalid.',
        );
      }
      if (state != 'active') continue;

      final id = _uuid(row['id'], 'Preparation block identity');
      final planId = _uuid(row['plan_id'], 'Preparation plan identity');
      final revision = row['revision'];
      final sequence = row['sequence'];
      final plannedMinutes = row['planned_minutes'];
      final startsAt = _awareDateTime(row['starts_at']);
      final endsAt = _awareDateTime(row['ends_at']);
      if (revision is! int ||
          revision < 1 ||
          revision > 200 ||
          sequence is! int ||
          sequence < 1 ||
          sequence > 120 ||
          plannedMinutes is! int ||
          plannedMinutes < 5 ||
          plannedMinutes > 240 ||
          endsAt.difference(startsAt) != Duration(minutes: plannedMinutes)) {
        throw const DeadlinePreparationScheduleException(
          'Active preparation block projection is invalid.',
        );
      }
      if (!seenBlockIds.add(id) ||
          !seenSequences.add('$planId|$revision|$sequence')) {
        throw const DeadlinePreparationScheduleException(
          'Preparation block result contains duplicates.',
        );
      }
      final plan = activePlans[planId];
      if (plan == null || plan.revision != revision) continue;
      result.add(
        DeadlinePreparationScheduleBlock(
          id: id,
          planId: planId,
          planTitle: plan.title,
          revision: revision,
          sequence: sequence,
          startsAt: startsAt,
          endsAt: endsAt,
          plannedMinutes: plannedMinutes,
        ),
      );
    }
    result.sort((left, right) {
      final byTime = left.startsAt.compareTo(right.startsAt);
      if (byTime != 0) return byTime;
      return left.id.compareTo(right.id);
    });
    return List.unmodifiable(result);
  }
}

class DeadlinePreparationScheduleException implements Exception {
  const DeadlinePreparationScheduleException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ActivePlanProjection {
  const _ActivePlanProjection(this.title, this.revision);

  final String title;
  final int revision;
}

const _reservationStates = {'proposed', 'active', 'superseded'};
const _planStatuses = {'draft', 'active', 'completed', 'cancelled'};
final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _awarePattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$',
);

String _uuid(Object? value, String label) {
  if (value is! String || !_uuidPattern.hasMatch(value)) {
    throw DeadlinePreparationScheduleException('$label is invalid.');
  }
  return value;
}

DateTime _awareDateTime(Object? value) {
  if (value is! String || !_awarePattern.hasMatch(value)) {
    throw const DeadlinePreparationScheduleException(
      'Preparation block instant is invalid.',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const DeadlinePreparationScheduleException(
      'Preparation block instant is invalid.',
    );
  }
  return parsed;
}

String _dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
